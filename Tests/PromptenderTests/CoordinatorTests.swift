import Foundation
import Testing
@testable import PromptenderKit

private final class CoordinatorMockTransport: HTTPTransportProtocol {
    let handler: (URLRequest) throws -> (Data, Int)

    init(handler: @escaping (URLRequest) throws -> (Data, Int)) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, status) = try handler(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1:31337")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

@Suite("PromptenderCoordinator Workflows & UI State")
struct CoordinatorTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("promptender-coord-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    @Test("Mix compiles offline, snapshots draft history, and restores previous draft cleanly")
    func mixAndDraftRestore() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = PromptenderCoordinator(
            recipeStore: RecipeStore(storageDirectoryURL: tempDir),
            secretStore: InMemorySecretStore()
        )

        let firstDraft = "three ceramic espresso cups on brushed aluminum counter lock:\"NEXUS COFFEE\""
        _ = coordinator.mixPrompt(rawInput: firstDraft, variables: [:], legacyOptions: EnhancementOptions())

        let secondDraft = "five neon cocktails under rain-soaked awning"
        let secondResult = coordinator.mixPrompt(rawInput: secondDraft, variables: [:], legacyOptions: EnhancementOptions())

        #expect(secondResult.compiledPrompt.contains("five neon cocktails"))
        #expect(coordinator.draftSnapshots.count == 2)

        let popped = coordinator.restorePreviousSnapshot()
        #expect(popped == secondDraft)
        let revertedToFirst = coordinator.restorePreviousSnapshot()
        #expect(revertedToFirst == firstDraft)
    }

    @MainActor
    @Test("House Specials persist to isolated RecipeStore and delete cleanly")
    func houseSpecialLifecycle() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RecipeStore(storageDirectoryURL: tempDir)
        let coordinator = PromptenderCoordinator(
            recipeStore: store,
            secretStore: InMemorySecretStore()
        )
        coordinator.selectedDestination = .openAIImage

        coordinator.saveCustomHouseSpecial(
            name: "Clean Studio Packaging",
            styleSuffix: "crisp product photography, diffused softbox lighting",
            defaultNegative: "clutter, watermark",
            mix: .neat
        )

        #expect(coordinator.customRecipes.count == 1)
        let saved = try #require(coordinator.customRecipes.first)
        #expect(saved.name == "Clean Studio Packaging")
        #expect(saved.isBuiltIn == false)
        #expect(coordinator.selectedRecipeID == saved.id)

        // Reload from disk via fresh store instance to confirm persistence
        let reloaded = RecipeStore(storageDirectoryURL: tempDir).loadCustomRecipes()
        #expect(reloaded.count == 1)

        coordinator.deleteCustomHouseSpecial(id: saved.id)
        #expect(coordinator.customRecipes.isEmpty)
        #expect(coordinator.selectedRecipeID != saved.id)
    }

    @MainActor
    @Test("Flight compiles all selected targets cleanly through coordinator")
    func coordinatorFlightCompilation() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = PromptenderCoordinator(
            recipeStore: RecipeStore(storageDirectoryURL: tempDir),
            secretStore: InMemorySecretStore()
        )
        coordinator.flightSelectedRecipeIDs = [
            "dexdiffusion-flux2-klein-4b",
            "xai-grok-imagine-image-2.0",
            "openai-gpt-6.1-sol-responses",
            "google-gemini-omni-1.2-flash"
        ]

        let report = coordinator.compileFlight(
            rawInput: "0s-4s: Neon tram glides past misty harbor. Audio: rain and soft bells.",
            variables: [:],
            legacyOptions: EnhancementOptions()
        )

        #expect(report.entries.count == 4)
        #expect(coordinator.lastFlightReport?.entries.count == 4)
        #expect(coordinator.statusBanner.contains("Flight compiled across 4 targets"))
    }

    @MainActor
    @Test("Keychain readiness transitions and DexDiffusion capability sync update readinessMap truthfully")
    func readinessTransitionsAndServeGate() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let secretStore = InMemorySecretStore()
        let capJSON = """
        {
          "configuration": { "degraded": false },
          "modelTargets": {
            "flux2-klein-4b": { "family": "flux", "engine": "mflux", "status": "available", "proofState": "proofed" },
            "sdxl-photonic": { "family": "sdxl", "engine": "sdcpp", "status": "dormant", "reason": "Offline in worker" }
          }
        }
        """.data(using: .utf8)!
        let verJSON = """
        { "name": "dexdiffusion", "version": "1.2.0", "gitHead": "abc1234", "pid": 42 }
        """.data(using: .utf8)!
        let wildJSON = """
        { "wildcards": [ { "name": "lighting", "count": 12 } ] }
        """.data(using: .utf8)!
        let schemaJSON = """
        { "required": ["prompt"], "properties": { "prompt": { "type": "string", "maxLength": 4000 } } }
        """.data(using: .utf8)!

        let transport = CoordinatorMockTransport { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("/api/capabilities") { return (capJSON, 200) }
            if path.hasSuffix("/api/version") { return (verJSON, 200) }
            if path.hasSuffix("/api/wildcards") { return (wildJSON, 200) }
            if path.hasSuffix("/api/generation-schema") { return (schemaJSON, 200) }
            return (Data(), 404)
        }

        let coordinator = PromptenderCoordinator(
            recipeStore: RecipeStore(storageDirectoryURL: tempDir),
            secretStore: secretStore,
            dexDiffusionClient: DexDiffusionClient(transport: transport)
        )

        // Initially no keys configured -> sourceImplemented
        #expect(coordinator.readinessMap["openai-gpt-image-2"] == .sourceImplemented)

        // Saving key in store marks OpenAI recipes availableToUser
        coordinator.saveAPIKey("sk-test-1234", for: .openAI)
        #expect(coordinator.readinessMap["openai-gpt-image-2"] == .availableToUser)

        // Refreshing DexDiffusion maps flux2-klein-4b -> capabilityProven and sdxl-photonic -> blocked
        await coordinator.refreshDexDiffusionStatus()
        #expect(coordinator.readinessMap["dexdiffusion-flux2-klein-4b"] == .capabilityProven)
        #expect(coordinator.dexDiffusionWildcards.first?.name == "lighting")

        // Valid mix opens PendingServeConfirmation with explicit destination & payload
        let CURRENT_TEST_DRAFT = "editorial shot of brass espresso machine"
        coordinator.selectedDestination = .dexDiffusionImage
        coordinator.selectedRecipeID = "dexdiffusion-flux2-klein-4b"
        _ = coordinator.mixPrompt(rawInput: CURRENT_TEST_DRAFT, variables: [:], legacyOptions: EnhancementOptions())
        coordinator.requestExternalServe(
            channel: .submitDexDiffusionControlled,
            rawInput: CURRENT_TEST_DRAFT,
            variables: [:],
            legacyOptions: EnhancementOptions()
        )
        #expect(coordinator.pendingServeConfirmation != nil)
        #expect(coordinator.pendingServeConfirmation?.modelID == "flux2-klein-4b")

        // Blocking invariant violation prevents Serve confirmation
        coordinator.pendingServeConfirmation = nil
        coordinator.selectedRecipeID = "dexdiffusion-sdxl-photonic"
        let hugeInput = String(repeating: "very detailed architectural photography ", count: 160)
        let blockedResult = coordinator.mixPrompt(rawInput: hugeInput, variables: [:], legacyOptions: EnhancementOptions())
        #expect(blockedResult.proofReport.hasBlockingIssues == true)
        coordinator.requestExternalServe(
            channel: .submitDexDiffusionControlled,
            rawInput: hugeInput,
            variables: [:],
            legacyOptions: EnhancementOptions()
        )
        #expect(coordinator.pendingServeConfirmation == nil)
    }

    @MainActor
    @Test("Compilation freshness tracks raw text, target, mode, variables, options, locks and references")
    func compileFreshnessTracksAllInputs() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let coordinator = PromptenderCoordinator(
            recipeStore: RecipeStore(storageDirectoryURL: dir),
            wildcardStore: WildcardStore(storageDirectoryURL: dir),
            secretStore: InMemorySecretStore()
        )
        var options = EnhancementOptions()
        let draft = "A precise editorial product photograph"
        let variables = ["brand": "original"]
        _ = coordinator.mixPrompt(rawInput: draft, variables: variables, legacyOptions: options)

        func fresh(_ raw: String = draft, _ vars: [String: String] = variables,
                   _ opts: EnhancementOptions = options) -> Bool {
            coordinator.isLastResultCurrent(rawInput: raw, variables: vars, legacyOptions: opts)
        }

        #expect(fresh())
        #expect(!fresh(draft + " changed"))
        #expect(!fresh(draft, ["brand": "modified"]))
        options.includeAlternatives.toggle()
        #expect(!fresh(draft, variables, options))
        options.includeAlternatives.toggle()
        #expect(fresh())

        coordinator.mixMode = .shaken
        #expect(!fresh())
        coordinator.mixMode = .stirred
        #expect(fresh())

        coordinator.selectedDestination = .grokImagineImage
        #expect(!fresh())
        coordinator.selectedDestination = .dexDiffusionImage
        coordinator.selectedRecipeID = "dexdiffusion-flux2-klein-4b"
        #expect(fresh())

        coordinator.manualLocks = ["KEEP EXACTLY"]
        #expect(!fresh())
        coordinator.manualLocks = []
        #expect(fresh())

        coordinator.parameterOverrides.width = 1024
        #expect(!fresh())
        coordinator.parameterOverrides.width = nil
        #expect(fresh())

        coordinator.attachedAssets = [
            ReferenceAsset(label: "Test source", pathOrURI: "/test.png", role: .style)
        ]
        #expect(!fresh())
        coordinator.attachedAssets = []
        #expect(fresh())

        coordinator.hintedIntent = .imageEdit
        #expect(!fresh())
        coordinator.hintedIntent = nil
        #expect(fresh())
    }

    @MainActor
    @Test("A stale draft cannot open confirmation or submit after confirmation opened")
    func staleResultNeverServes() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var sent = [String]()
        let transport = CoordinatorMockTransport { request in
            sent.append(request.httpMethod ?? "GET")
            return (Data(), 503)
        }
        let coordinator = PromptenderCoordinator(
            recipeStore: RecipeStore(storageDirectoryURL: dir),
            wildcardStore: WildcardStore(storageDirectoryURL: dir),
            secretStore: InMemorySecretStore(),
            dexDiffusionClient: DexDiffusionClient(transport: transport)
        )
        let options = EnhancementOptions()
        let draft = "editorial photo of a midnight-blue compass"
        _ = coordinator.mixPrompt(rawInput: draft, variables: [:], legacyOptions: options)
        coordinator.requestExternalServe(
            channel: .submitDexDiffusionControlled,
            rawInput: draft + " modified", variables: [:], legacyOptions: options
        )
        #expect(coordinator.pendingServeConfirmation == nil)
        #expect(coordinator.statusBanner.contains("Mix again"))

        coordinator.requestExternalServe(
            channel: .submitDexDiffusionControlled,
            rawInput: draft, variables: [:], legacyOptions: options
        )
        #expect(coordinator.pendingServeConfirmation != nil)
        await coordinator.confirmAndExecutePendingServe(
            rawInput: draft + " modified", variables: [:], legacyOptions: options
        )
        #expect(coordinator.pendingServeConfirmation == nil)
        #expect(coordinator.statusBanner.contains("Mix again"))
        #expect(sent.isEmpty)
    }

    @MainActor
    @Test("Wildcard catalogue revisions invalidate results only when wildcard expansion was enabled")
    func wildcardRevisionInvalidation() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let coordinator = PromptenderCoordinator(
            recipeStore: RecipeStore(storageDirectoryURL: dir),
            wildcardStore: WildcardStore(storageDirectoryURL: dir),
            secretStore: InMemorySecretStore()
        )
        let opts = EnhancementOptions()
        let input = "A studio object with __lighting__"
        coordinator.expandWildcardsOnMix = false
        _ = coordinator.mixPrompt(rawInput: input, variables: [:], legacyOptions: opts)
        let saved = await coordinator.saveWildcardBank(
            name: "fresh_bank", items: ["good"], description: "", tags: []
        )
        #expect(saved)
        #expect(coordinator.isLastResultCurrent(rawInput: input, variables: [:], legacyOptions: opts))
        coordinator.expandWildcardsOnMix = true
        _ = coordinator.mixPrompt(rawInput: input, variables: [:], legacyOptions: opts)
        #expect(coordinator.isLastResultCurrent(rawInput: input, variables: [:], legacyOptions: opts))
        let updated = await coordinator.saveWildcardBank(
            name: "another_bank", items: ["new"], description: "", tags: []
        )
        #expect(updated)
        #expect(!coordinator.isLastResultCurrent(rawInput: input, variables: [:], legacyOptions: opts))
    }

}
