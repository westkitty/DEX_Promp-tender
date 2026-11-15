import Foundation
import Testing
@testable import PromptenderKit

private final class WildcardSyncMockTransport: HTTPTransportProtocol {
    var recordedRequests: [URLRequest] = []
    var rejectRemoteDelete = false
    var rejectRemotePut = false
    var mutateOnSecondRead: String? = nil
    var readCounts: [String: Int] = [:]
    var banks: [String: (items: [String], desc: String, tags: [String])] = [
        "custom_neon": (["magenta tube reflection", "sodium amber glow"], "Neon colors", ["lighting"])
    ]

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recordedRequests.append(request)
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"

        func jsonResponse(_ obj: Any, status: Int = 200) -> (Data, HTTPURLResponse) {
            let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
            let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (data, resp)
        }

        if path == "/api/wildcards", method == "GET" {
            let list: [[String: Any]] = banks.sorted(by: { $0.key < $1.key }).map { name, entry in
                [
                    "name": name,
                    "count": entry.items.count,
                    "preview": Array(entry.items.prefix(3)),
                    "description": entry.desc,
                    "tags": entry.tags,
                    "source": "user"
                ]
            }
            return jsonResponse(["wildcards": list])
        }

        if path.hasPrefix("/api/wildcards/"), path != "/api/wildcards/expand" {
            let name = String(path.dropFirst("/api/wildcards/".count))
            if method == "GET" {
                readCounts[name, default: 0] += 1
                if mutateOnSecondRead == name, readCounts[name] == 2 {
                    banks[name] = (["concurrent owner edit"], "Changed elsewhere", ["changed"])
                }
                guard let entry = banks[name] else { return jsonResponse(["error": "Not found"], status: 404) }
                return jsonResponse([
                    "name": name,
                    "count": entry.items.count,
                    "items": entry.items,
                    "description": entry.desc,
                    "tags": entry.tags,
                    "source": "user"
                ])
            }
            if method == "PUT", rejectRemotePut {
                return jsonResponse(["error": "Simulated PUT failure"], status: 503)
            }
            if method == "PUT",
               let body = request.httpBody,
               let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let items = dict["items"] as? [String] {
                let desc = (dict["description"] as? String) ?? ""
                let tags = (dict["tags"] as? [String]) ?? []
                banks[name] = (items, desc, tags)
                return jsonResponse(["name": name, "count": items.count])
            }
            if method == "DELETE", rejectRemoteDelete {
                return jsonResponse(["error": "Simulated DELETE failure"], status: 503)
            }
            if method == "DELETE" {
                banks.removeValue(forKey: name)
                return jsonResponse(["removed": true])
            }
        }

        return jsonResponse([:])
    }
}

@Suite("Wildcards Sync, Enhancement Quality, Prompt Saving & Appearance")
struct WildcardAppearanceEnhancementTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("promptender-wac-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Built-in wildcards load offline and expand __tokens__ deterministically")
    func builtInWildcardsAndExpansion() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WildcardStore(storageDirectoryURL: tempDir)
        let banks = store.loadAllLocalBanks()

        #expect(banks.contains(where: { $0.name == "lighting" }))
        #expect(banks.contains(where: { $0.name == "colors" }))
        #expect(banks.contains(where: { $0.name == "camera_perspectives" }))

        let expanded = store.expandTokens(
            in: "A samurai in __lighting__ with __nonexistent_bank__",
            banks: banks,
            seed: 42
        )
        #expect(!expanded.contains("__lighting__"))
        #expect(expanded.contains("__nonexistent_bank__"))
    }

    @MainActor
    @Test("Wildcard writes and deletion are scoped: local first; remote and folder only by explicit choice")
    func wildcardBidirectionalSync() async throws {
        let appDir = try makeTempDir()
        let extDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: appDir)
            try? FileManager.default.removeItem(at: extDir)
        }

        let transport = WildcardSyncMockTransport()
        let store = WildcardStore(storageDirectoryURL: appDir)
        let coordinator = PromptenderCoordinator(
            recipeStore: RecipeStore(storageDirectoryURL: appDir),
            wildcardStore: store,
            secretStore: InMemorySecretStore(),
            dexDiffusionClient: DexDiffusionClient(transport: transport)
        )
        coordinator.setWildcardSyncDirectory(extDir.path)

        await coordinator.refreshDexDiffusionStatus()
        #expect(coordinator.wildcardBanks.contains(where: { $0.name == "custom_neon" }))

        let detail = await coordinator.loadWildcardBankDetail(name: "custom_neon")
        #expect(detail?.items.count == 2)

        let saved = await coordinator.saveWildcardBank(
            name: "chrome_materials",
            items: ["brushed titanium", "anodized graphite", "brushed titanium"],
            description: "Metallic finishes",
            tags: ["materials", "metal"]
        )
        #expect(saved)
        #expect(store.hasLocalBank(name: "chrome_materials"))
        #expect(!store.hasSyncedBank(name: "chrome_materials"))
        #expect(transport.banks["chrome_materials"] == nil)
        #expect(!transport.recordedRequests.contains(where: { $0.httpMethod == "PUT" || $0.httpMethod == "DELETE" }))

        let synced = await coordinator.syncWildcardBank(
            name: "chrome_materials",
            items: ["brushed titanium", "anodized graphite", "brushed titanium"],
            description: "Metallic finishes",
            tags: ["materials", "metal"],
            toFolder: true, toRemote: true,
            allowFolderOverwrite: false, allowRemoteOverwrite: false
        )
        #expect(synced)
        #expect(store.hasSyncedBank(name: "chrome_materials"))
        #expect(transport.banks["chrome_materials"]?.items.count == 2)

        let localOnly = await coordinator.deleteWildcardBank(
            name: "chrome_materials", local: true, syncedFolder: false, remote: false
        )
        #expect(localOnly)
        #expect(!store.hasLocalBank(name: "chrome_materials"))
        #expect(store.hasSyncedBank(name: "chrome_materials"))
        #expect(transport.banks["chrome_materials"] != nil)
        #expect(!transport.recordedRequests.contains(where: { $0.httpMethod == "DELETE" }))

        let deleted = await coordinator.deleteWildcardBank(
            name: "chrome_materials", local: false, syncedFolder: true, remote: true
        )
        #expect(deleted)
        #expect(!store.hasSyncedBank(name: "chrome_materials"))
        #expect(transport.banks["chrome_materials"] == nil)

        let backups = appDir.appendingPathComponent("WildcardBackups", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        #expect(files.contains(where: { $0.hasPrefix("local-") }))
        #expect(files.contains(where: { $0.hasPrefix("folder-") }))
        #expect(files.contains(where: { $0.hasPrefix("remote-") }))
    }

    @MainActor
    @Test("Remote overwrites require explicit approval and produce a backup")
    func remoteOverwriteIsOptIn() async throws {
        let appDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: appDir) }
        let transport = WildcardSyncMockTransport()
        let store = WildcardStore(storageDirectoryURL: appDir)
        let coordinator = PromptenderCoordinator(
            recipeStore: RecipeStore(storageDirectoryURL: appDir),
            wildcardStore: store, secretStore: InMemorySecretStore(),
            dexDiffusionClient: DexDiffusionClient(transport: transport)
        )
        let rejected = await coordinator.syncWildcardBank(
            name: "custom_neon", items: ["new entry"], description: "new", tags: [],
            toFolder: false, toRemote: true,
            allowFolderOverwrite: false, allowRemoteOverwrite: false
        )
        #expect(!rejected)
        #expect(transport.banks["custom_neon"]?.items.count == 2)
        #expect(!store.hasLocalBank(name: "custom_neon"))
        #expect(!transport.recordedRequests.contains(where: { $0.httpMethod == "PUT" }))

        let accepted = await coordinator.syncWildcardBank(
            name: "custom_neon", items: ["new entry"], description: "new", tags: [],
            toFolder: false, toRemote: true,
            allowFolderOverwrite: false, allowRemoteOverwrite: true
        )
        #expect(accepted)
        #expect(transport.banks["custom_neon"]?.items == ["new entry"])
        let backups = appDir.appendingPathComponent("WildcardBackups", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        #expect(files.contains(where: { $0.hasPrefix("remote-") }))
    }

    @MainActor
    @Test("Remote deletion failure is surfaced without claiming success; remote stays intact")
    func remoteDeletionFailureIsReported() async throws {
        let appDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: appDir) }
        let transport = WildcardSyncMockTransport()
        transport.rejectRemoteDelete = true
        let store = WildcardStore(storageDirectoryURL: appDir)
        _ = try store.saveBankLocally(
            name: "custom_neon", items: ["local"], description: "", tags: []
        )
        let coordinator = PromptenderCoordinator(
            recipeStore: RecipeStore(storageDirectoryURL: appDir),
            wildcardStore: store, secretStore: InMemorySecretStore(),
            dexDiffusionClient: DexDiffusionClient(transport: transport)
        )
        let deleted = await coordinator.deleteWildcardBank(
            name: "custom_neon", local: true, syncedFolder: false, remote: true
        )
        #expect(!deleted)
        #expect(!store.hasLocalBank(name: "custom_neon"))
        #expect(transport.banks["custom_neon"] != nil)
        #expect(coordinator.statusBanner.contains("incomplete"))
        #expect(coordinator.latestWildcardOperationReceipt?.failed.isEmpty == false)
        #expect(coordinator.latestWildcardOperationReceipt?.completed.contains("local") == true)
        let backups = appDir.appendingPathComponent("WildcardBackups", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        #expect(files.contains(where: { $0.hasPrefix("local-") }))
        #expect(files.contains(where: { $0.hasPrefix("remote-") }))
    }

    @MainActor
    @Test("Built-in wildcard banks cannot be saved, mirrored, or deleted")
    func builtInBanksAreProtected() async throws {
        let appDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: appDir) }
        let store = WildcardStore(storageDirectoryURL: appDir)
        #expect(store.isBundledBank(name: "lighting"))
        #expect(!store.hasLocalBank(name: "lighting"))

        do {
            _ = try store.saveBankLocally(
                name: "lighting", items: ["overwrite"], description: "", tags: []
            )
            Issue.record("Expected protected built-in write to fail.")
        } catch {}
        do {
            _ = try store.deleteBankCopies(name: "lighting", local: true, syncedFolder: false)
            Issue.record("Expected protected built-in deletion to fail.")
        } catch {}

        let transport = WildcardSyncMockTransport()
        let coordinator = PromptenderCoordinator(
            recipeStore: RecipeStore(storageDirectoryURL: appDir),
            wildcardStore: store, secretStore: InMemorySecretStore(),
            dexDiffusionClient: DexDiffusionClient(transport: transport)
        )
        let remoteDeletion = await coordinator.deleteWildcardBank(
            name: "lighting", local: false, syncedFolder: false, remote: true
        )
        #expect(!remoteDeletion)
        #expect(!transport.recordedRequests.contains(where: { $0.httpMethod == "DELETE" }))
    }

    @MainActor
    @Test("Unavailable folder and failed remote PUT do not silently report full sync")
    func syncFailureEvidence() async throws {
        let appDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: appDir) }
        let transport = WildcardSyncMockTransport()
        transport.rejectRemotePut = true
        let store = WildcardStore(storageDirectoryURL: appDir)
        let coordinator = PromptenderCoordinator(
            recipeStore: RecipeStore(storageDirectoryURL: appDir),
            wildcardStore: store, secretStore: InMemorySecretStore(),
            dexDiffusionClient: DexDiffusionClient(transport: transport)
        )
        coordinator.setWildcardSyncDirectory(
            appDir.appendingPathComponent("missing-folder").path
        )
        let failedFolder = await coordinator.syncWildcardBank(
            name: "new_bank", items: ["test"], description: "", tags: [],
            toFolder: true, toRemote: false,
            allowFolderOverwrite: false, allowRemoteOverwrite: false
        )
        #expect(!failedFolder)
        #expect(!store.hasLocalBank(name: "new_bank"))

        let failedRemote = await coordinator.syncWildcardBank(
            name: "custom_neon", items: ["replaced"], description: "", tags: [],
            toFolder: false, toRemote: true,
            allowFolderOverwrite: false, allowRemoteOverwrite: true
        )
        #expect(!failedRemote)
        #expect(coordinator.statusBanner.contains("PARTIAL sync"))
        #expect(transport.banks["custom_neon"]?.items.count == 2)
    }

    @MainActor
    @Test("A changed remote bank blocks a stale overwrite without PUT")
    func concurrentRemoteOverwriteIsRejected() async throws {
        let appDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: appDir) }
        let transport = WildcardSyncMockTransport()
        transport.mutateOnSecondRead = "custom_neon"
        let coordinator = PromptenderCoordinator(
            recipeStore: RecipeStore(storageDirectoryURL: appDir),
            wildcardStore: WildcardStore(storageDirectoryURL: appDir),
            secretStore: InMemorySecretStore(),
            dexDiffusionClient: DexDiffusionClient(transport: transport)
        )
        let result = await coordinator.syncWildcardBank(
            name: "custom_neon", items: ["replacement"], description: "mine", tags: [],
            toFolder: false, toRemote: true,
            allowFolderOverwrite: false, allowRemoteOverwrite: true
        )
        #expect(!result)
        #expect(transport.banks["custom_neon"]?.items == ["concurrent owner edit"])
        #expect(!transport.recordedRequests.contains(where: { $0.httpMethod == "PUT" }))
        #expect(coordinator.statusBanner.contains("changed since preflight"))
    }

    @MainActor
    @Test("A changed remote bank blocks stale deletion without DELETE")
    func concurrentRemoteDeleteIsRejected() async throws {
        let appDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: appDir) }
        let transport = WildcardSyncMockTransport()
        transport.mutateOnSecondRead = "custom_neon"
        let coordinator = PromptenderCoordinator(
            recipeStore: RecipeStore(storageDirectoryURL: appDir),
            wildcardStore: WildcardStore(storageDirectoryURL: appDir),
            secretStore: InMemorySecretStore(),
            dexDiffusionClient: DexDiffusionClient(transport: transport)
        )
        let deleted = await coordinator.deleteWildcardBank(
            name: "custom_neon", local: false, syncedFolder: false, remote: true
        )
        #expect(!deleted)
        #expect(transport.banks["custom_neon"]?.items == ["concurrent owner edit"])
        #expect(!transport.recordedRequests.contains(where: { $0.httpMethod == "DELETE" }))
        #expect(coordinator.statusBanner.contains("changed since preflight"))
    }

    @Test("Folder overwrite is denied by default, then backed up when explicitly authorized")
    func folderOverwriteRequiresAuthorization() throws {
        let appDir = try makeTempDir()
        let syncDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: appDir)
            try? FileManager.default.removeItem(at: syncDir)
        }
        let store = WildcardStore(storageDirectoryURL: appDir)
        store.saveSyncConfig(WildcardSyncConfig(externalSyncDirectoryPath: syncDir.path))
        let bankFile = syncDir.appendingPathComponent("danger_zone.txt")
        try "original, do not lose me\n".write(to: bankFile, atomically: true, encoding: .utf8)
        do {
            _ = try store.mirrorBankToSyncFolder(
                name: "danger_zone", items: ["replacement"], description: "", tags: [],
                allowOverwrite: false
            )
            Issue.record("Unexpected overwrite without explicit approval.")
        } catch {}
        #expect(try String(contentsOf: bankFile, encoding: .utf8) == "original, do not lose me\n")

        let changed = try store.mirrorBankToSyncFolder(
            name: "danger_zone", items: ["replacement"], description: "", tags: [],
            allowOverwrite: true
        )
        #expect(changed == "updated")
        #expect(try String(contentsOf: bankFile, encoding: .utf8).contains("replacement"))
        let backupDir = appDir.appendingPathComponent("WildcardBackups", isDirectory: true)
        let backups = try FileManager.default.contentsOfDirectory(
            at: backupDir, includingPropertiesForKeys: nil
        )
        #expect(backups.contains(where: { $0.lastPathComponent.hasPrefix("folder-") }))
        let backupContents = try backups.map { try String(contentsOf: $0, encoding: .utf8) }
        #expect(backupContents.contains("original, do not lose me\n"))
    }

    @Test("Saving an existing local bank preserves its previous content in backups")
    func localOverwriteCreatesBackup() throws {
        let appDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: appDir) }
        let store = WildcardStore(storageDirectoryURL: appDir)
        _ = try store.saveBankLocally(
            name: "local_changes", items: ["original"], description: "", tags: []
        )
        _ = try store.saveBankLocally(
            name: "local_changes", items: ["replacement"], description: "", tags: []
        )
        let backupDir = appDir.appendingPathComponent("WildcardBackups", isDirectory: true)
        let backups = try FileManager.default.contentsOfDirectory(
            at: backupDir, includingPropertiesForKeys: nil
        )
        #expect(backups.contains(where: { $0.lastPathComponent.hasPrefix("local-") }))
        let backupContents = try backups.map { try String(contentsOf: $0, encoding: .utf8) }
        #expect(backupContents.contains("original\n"))
    }

    @Test("Stirred and Shaken meaningfully enhance both sparse visual prompts and short text drafts")
    func meaningfulEnhancementAcrossImageAndText() {
        let engine = PromptCompilerEngine()
        let imageRecipe = engine.registry.defaultRecipe(for: .dexDiffusionImage)
        let casualImageInput = "a cybernetic owl perched on a rain-slicked pagoda"

        let imageStirred = engine.compile(
            rawInput: casualImageInput,
            recipe: imageRecipe,
            mixMode: .stirred
        )
        #expect(imageStirred.compiledPrompt.count > casualImageInput.count + 40)
        #expect(imageStirred.compiledPrompt.contains("cybernetic owl"))

        let imageShaken = engine.compile(
            rawInput: casualImageInput,
            recipe: imageRecipe,
            mixMode: .shaken
        )
        #expect(imageShaken.compiledPrompt.count > imageStirred.compiledPrompt.count)

        let textRecipe = engine.registry.defaultRecipe(for: .openAITextAgent)
        let casualTextInput = "help me plan a product launch email"
        let textStirred = engine.compile(
            rawInput: casualTextInput,
            recipe: textRecipe,
            mixMode: .stirred
        )
        #expect(textStirred.compiledPrompt.count > casualTextInput.count + 50)
        #expect(textStirred.compiledPrompt.contains("product launch email"))
    }

    @MainActor
    @Test("Quick Save Prompt persists into Cellar Library + Templates + History")
    func quickPromptSavingAndHistory() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testAppFolder = "DexPromptender-Test-\(UUID().uuidString)"
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(testAppFolder, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: appSupportDir) }

        let storageBackend = InMemoryStorageBackend()
        let repo = PromptLibraryRepository(storageBackend: storageBackend)
        let vm = PromptEngineViewModel(
            storageManager: StorageManager(appFolderName: testAppFolder),
            promptLibraryRepository: repo
        )
        let coordinator = PromptenderCoordinator(
            recipeStore: RecipeStore(storageDirectoryURL: tempDir),
            wildcardStore: WildcardStore(storageDirectoryURL: tempDir),
            secretStore: InMemorySecretStore()
        )

        let result = coordinator.mixPrompt(rawInput: "cinematic portrait of a watchmaker", variables: [:], legacyOptions: EnhancementOptions())
        vm.recordCompiledMixHistory(target: result.target, originalInput: "cinematic portrait of a watchmaker", compiledPrompt: result.compiledPrompt)
        coordinator.savePromptQuickly(
            title: "Watchmaker Study",
            body: result.compiledPrompt,
            saveToLibrary: true,
            saveAsTemplate: true,
            into: vm
        )

        #expect(vm.promptLibraryPrompts.contains(where: { $0.title == "Watchmaker Study" }))
        #expect(vm.templates.contains(where: { $0.name == "Watchmaker Study" }))
        #expect(vm.history.first?.generatedPrompt == result.compiledPrompt)
    }

    @MainActor
    @Test("AppearanceSettingsStore persists custom watermark, behind image, and resets cleanly")
    func appearanceSettingsPersistence() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("appearance-settings.json")
        let store = AppearanceSettingsStore(fileURL: fileURL)
        store.settings.watermarkOpacity = 0.25
        store.settings.watermarkScale = 1.4
        store.settings.watermarkBlendMode = .overlay
        store.settings.isBackdropImageEnabled = true
        store.settings.backdropBlur = 12.0
        store.settings.customBackdropImagePath = "/tmp/sample-backdrop.png"
        store.flushPendingSave()

        let reloaded = AppearanceSettingsStore(fileURL: fileURL)
        #expect(reloaded.settings.watermarkOpacity == 0.25)
        #expect(reloaded.settings.watermarkScale == 1.4)
        #expect(reloaded.settings.watermarkBlendMode == .overlay)
        #expect(reloaded.settings.isBackdropImageEnabled == true)
        #expect(reloaded.settings.backdropBlur == 12.0)

        reloaded.resetToDefaults()
        #expect(reloaded.settings == .default)
    }
}
