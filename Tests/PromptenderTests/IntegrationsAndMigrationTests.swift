import Foundation
import Testing
@testable import PromptenderKit

private final class MockHTTPTransport: HTTPTransportProtocol {
    var handler: (URLRequest) throws -> (Data, Int)
    private(set) var recordedRequests: [URLRequest] = []

    init(handler: @escaping (URLRequest) throws -> (Data, Int)) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recordedRequests.append(request)
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

@Suite("Integrations, Safety Gates & Non-Destructive Import")
struct IntegrationsAndMigrationTests {
    @Test("DexDiffusionClient maps live capability states truthfully and enforces Serve gates")
    func dexDiffusionCapabilitiesAndServeGates() async throws {
        let capJSON = """
        {
          "configuration": { "degraded": true },
          "editWorkerTarget": "sd15",
          "modelTargets": {
            "flux2-klein-4b": { "family": "flux", "engine": "mflux", "status": "available", "proofState": "proofed" },
            "sdxl-photonic": { "family": "sdxl", "engine": "sdcpp", "status": "available", "proofState": "staged" },
            "sd15": { "family": "sd15", "engine": "sdcpp", "status": "dormant", "reason": "External weights locked" }
          }
        }
        """.data(using: .utf8)!

        let transport = MockHTTPTransport { req in
            if req.url?.path.hasSuffix("/api/capabilities") == true {
                return (capJSON, 200)
            }
            if req.url?.path.hasSuffix("/api/actions/generate-controlled") == true {
                return (#"{"jobId":"job-123","status":"QUEUED"}"#.data(using: .utf8)!, 200)
            }
            return (Data("{}".utf8), 404)
        }

        let client = DexDiffusionClient(transport: transport)
        let snapshot = await client.fetchCapabilities()

        #expect(snapshot.reachable == true)
        #expect(snapshot.configurationDegraded == true)
        #expect(snapshot.targets.first(where: { $0.id == "flux2-klein-4b" })?.readinessState == .capabilityProven)
        #expect(snapshot.targets.first(where: { $0.id == "sdxl-photonic" })?.readinessState == .capabilityAdvertised)
        #expect(snapshot.targets.first(where: { $0.id == "sd15" })?.readinessState == .blocked(reason: "External weights locked"))

        // Gate check 1: wrong channel token fails
        let engine = PromptCompilerEngine()
        let recipe = engine.registry.recipe(for: "dexdiffusion-flux2-klein-4b")!
        let validCompiled = engine.compile(rawInput: "A glowing compass on oak desk", recipe: recipe, mixMode: .stirred)

        await #expect(throws: DexDiffusionClientError.self) {
            _ = try await client.submitControlledGeneration(
                result: validCompiled,
                authorization: ServeAuthorizationToken(channel: .copyPrompt, targetID: recipe.id)
            )
        }

        // Gate check 2: oversized prompt fails even with valid token
        let oversizedCompiled = engine.compile(
            rawInput: String(repeating: "copper lantern in fog, ", count: 220),
            recipe: recipe,
            mixMode: .neat
        )
        await #expect(throws: DexDiffusionClientError.self) {
            _ = try await client.submitControlledGeneration(
                result: oversizedCompiled,
                authorization: ServeAuthorizationToken(channel: .submitDexDiffusionControlled, targetID: recipe.id)
            )
        }
        #expect(transport.recordedRequests.count == 1) // Only GET /api/capabilities fired so far!

        // Gate check 3: valid token + non-blocking proof succeeds
        let responseText = try await client.submitControlledGeneration(
            result: validCompiled,
            authorization: ServeAuthorizationToken(channel: .submitDexDiffusionControlled, targetID: recipe.id)
        )
        #expect(responseText.contains("job-123"))
        #expect(transport.recordedRequests.count == 2)
    }

    @Test("ProviderAPIRouter redacts secrets and requires explicit authorization before network POST")
    func providerAPISecurityAndGates() async throws {
        let secretStore = InMemorySecretStore()
        try secretStore.saveSecret("xai-test-secret-do-not-leak", for: .xai)

        let transport = MockHTTPTransport { _ in
            (#"{"data":[{"url":"https://example.invalid/out.png"}]}"#.data(using: .utf8)!, 200)
        }
        let router = ProviderAPIRouter(secretStore: secretStore, transport: transport)
        let engine = PromptCompilerEngine()
        let grokImg = engine.registry.recipe(for: "xai-grok-imagine-image-2.0")!
        let result = engine.compile(rawInput: "Steampunk observatory at midnight", recipe: grokImg, mixMode: .stirred)

        // Preview never includes raw API key
        let preview = try router.buildRedactedRequestPreview(for: result)
        #expect(preview.url == "https://api.x.ai/v1/images/generations")
        #expect(!(preview.headers["Authorization"] ?? "").contains("xai-test-secret-do-not-leak"))
        #expect(transport.recordedRequests.isEmpty)

        // Unauthorized token blocked before network call
        await #expect(throws: ProviderGatewayError.self) {
            _ = try await router.submit(
                result: result,
                authorization: ServeAuthorizationToken(channel: .copyPayloadJSON, targetID: grokImg.id)
            )
        }
        #expect(transport.recordedRequests.isEmpty)

        // Explicit authorized token sends safely
        let receipt = try await router.submit(
            result: result,
            authorization: ServeAuthorizationToken(channel: .submitAuthorizedProviderAPI, targetID: grokImg.id)
        )
        #expect(receipt.statusCode == 200)
        #expect(transport.recordedRequests.count == 1)
    }

    @Test("DexCraftImportService imports read-only, creates destination backup, and deduplicates cleanly")
    func nonDestructiveDexCraftImport() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("PromptenderImportTest-\(UUID().uuidString)", isDirectory: true)
        let srcDir = tempRoot.appendingPathComponent("DexCraft", isDirectory: true)
        let dstDir = tempRoot.appendingPathComponent("DexPromptender", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let sharedID = UUID()
        let legacyT1 = PromptTemplate(id: sharedID, name: "Legacy Alpha", content: "Legacy content A", target: .claude, category: "Dev", tags: ["test"])
        let legacyT2 = PromptTemplate(id: UUID(), name: "Legacy Beta", content: "Legacy content B", target: .geminiChatGPT, category: "Img", tags: [])
        try encoder.encode([legacyT1, legacyT2]).write(to: srcDir.appendingPathComponent("templates.json"))

        let existingDestT1 = PromptTemplate(id: sharedID, name: "Custom Promptender Override", content: "Existing kept", target: .claude, category: "Dev", tags: [])
        try encoder.encode([existingDestT1]).write(to: dstDir.appendingPathComponent("templates.json"))

        let sourceBytesBefore = try Data(contentsOf: srcDir.appendingPathComponent("templates.json"))

        let importer = DexCraftImportService(sourceDirURL: srcDir, destinationDirURL: dstDir)
        let report = try importer.importLegacyData()

        #expect(report.templatesImported == 1)
        #expect(report.templatesSkippedDuplicates == 1)
        #expect(report.backupDirectoryPath != nil)
        if let backupPath = report.backupDirectoryPath {
            #expect(fm.fileExists(atPath: backupPath + "/templates.json"))
        }

        // Verify source untouched byte-for-byte
        let sourceBytesAfter = try Data(contentsOf: srcDir.appendingPathComponent("templates.json"))
        #expect(sourceBytesBefore == sourceBytesAfter)

        // Verify destination preserved existing Custom override + merged Legacy Beta
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let merged = try decoder.decode([PromptTemplate].self, from: Data(contentsOf: dstDir.appendingPathComponent("templates.json")))
        #expect(merged.count == 2)
        #expect(merged.first(where: { $0.id == sharedID })?.name == "Custom Promptender Override")
    }

    @Test("RecipeStore persists and removes custom House Specials cleanly")
    func recipeStorePersistence() {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("RecipeStoreTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: dir) }

        let store = RecipeStore(storageDirectoryURL: dir)
        let custom = RecipeProfile(
            id: "custom-noir-flux",
            version: "1.0.0",
            name: "Rainy Noir FLUX Special",
            destination: .dexDiffusionImage,
            modelID: "flux2-klein-4b",
            subtitle: "Custom atmospheric contrast",
            promptDialectNote: "Custom preset",
            defaultMixMode: .shaken,
            systemPrelude: "",
            styleSuffix: "anamorphic 35mm grain, wet asphalt reflections",
            defaultNegativePrompt: "",
            isBuiltIn: false,
            constraints: RecipeConstraints(maxPromptCharacters: 4000, maxReferenceAssets: 1, supportsNegativePromptField: true)
        )

        let afterAdd = store.upsertCustomRecipe(custom)
        #expect(afterAdd.count == 1)
        #expect(store.loadCustomRecipes().first?.id == "custom-noir-flux")

        let afterDelete = store.deleteCustomRecipe(id: "custom-noir-flux")
        #expect(afterDelete.isEmpty)
    }
}
