import Foundation
import Testing
@testable import PromptenderKit

private final class WildcardSyncMockTransport: HTTPTransportProtocol {
    var recordedRequests: [URLRequest] = []
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
            if method == "PUT",
               let body = request.httpBody,
               let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let items = dict["items"] as? [String] {
                let desc = (dict["description"] as? String) ?? ""
                let tags = (dict["tags"] as? [String]) ?? []
                banks[name] = (items, desc, tags)
                return jsonResponse(["name": name, "count": items.count])
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
    @Test("Wildcards editor saves to external sync folder and pushes PUT/DELETE to Dexter Fusion API")
    func wildcardBidirectionalSync() async throws {
        let appDir = try makeTempDir()
        let extDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: appDir)
            try? FileManager.default.removeItem(at: extDir)
        }

        let transport = WildcardSyncMockTransport()
        let coordinator = PromptenderCoordinator(
            recipeStore: RecipeStore(storageDirectoryURL: appDir),
            wildcardStore: WildcardStore(storageDirectoryURL: appDir),
            secretStore: InMemorySecretStore(),
            dexDiffusionClient: DexDiffusionClient(transport: transport)
        )
        coordinator.setWildcardSyncDirectory(extDir.path)

        await coordinator.refreshDexDiffusionStatus()
        #expect(coordinator.wildcardBanks.contains(where: { $0.name == "custom_neon" }))

        let detail = await coordinator.loadWildcardBankDetail(name: "custom_neon")
        #expect(detail?.items.count == 2)

        await coordinator.saveWildcardBank(
            name: "chrome_materials",
            items: ["brushed titanium", "anodized graphite", "brushed titanium"],
            description: "Metallic finishes",
            tags: ["materials", "metal"]
        )

        #expect(transport.banks["chrome_materials"]?.items.count == 2)
        let mirroredFile = extDir.appendingPathComponent("chrome_materials.txt")
        #expect(FileManager.default.fileExists(atPath: mirroredFile.path))

        await coordinator.deleteWildcardBank(name: "chrome_materials")
        #expect(transport.banks["chrome_materials"] == nil)
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
