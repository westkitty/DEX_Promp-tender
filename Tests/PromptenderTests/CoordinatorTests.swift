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
        coordinator.selectedDestination = .dexDiffusionImage
        coordinator.selectedRecipeID = "dexdiffusion-flux2-klein-4b"
        _ = coordinator.mixPrompt(rawInput: "editorial shot of brass espresso machine", variables: [:], legacyOptions: EnhancementOptions())
        coordinator.requestExternalServe(channel: .submitDexDiffusionControlled)
        #expect(coordinator.pendingServeConfirmation != nil)
        #expect(coordinator.pendingServeConfirmation?.modelID == "flux2-klein-4b")

        // Blocking invariant violation prevents Serve confirmation
        coordinator.pendingServeConfirmation = nil
        coordinator.selectedRecipeID = "dexdiffusion-sdxl-photonic"
        let hugeInput = String(repeating: "very detailed architectural photography ", count: 160)
        let blockedResult = coordinator.mixPrompt(rawInput: hugeInput, variables: [:], legacyOptions: EnhancementOptions())
        #expect(blockedResult.proofReport.hasBlockingIssues == true)
        coordinator.requestExternalServe(channel: .submitDexDiffusionControlled)
        #expect(coordinator.pendingServeConfirmation == nil)
    }
}
