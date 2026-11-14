import AppKit
import Foundation
import SwiftUI

struct PendingServeConfirmation: Identifiable {
    let id = UUID()
    let channel: ServeChannel
    let destinationTitle: String
    let endpointURL: String
    let modelID: String
    let redactedHeaders: [String: String]
    let payloadPreview: String
    let billingNotice: String
    let result: CompilationResult
}

@MainActor
final class PromptenderCoordinator: ObservableObject {
    let compilerEngine: PromptCompilerEngine
    let flightEngine: FlightEngine
    let recipeStore: RecipeStore
    let wildcardStore: WildcardStore
    let secretStore: SecretStoreProtocol
    let dexDiffusionClient: DexDiffusionClient
    let providerRouter: ProviderAPIRouter
    let importService: DexCraftImportService

    @Published var selectedDestination: TargetDestination = .dexDiffusionImage {
        didSet {
            if let first = availableRecipes(for: selectedDestination).first {
                selectedRecipeID = first.id
            }
        }
    }
    @Published var selectedRecipeID: String = "dexdiffusion-flux2-klein-4b"
    @Published var mixMode: MixMode = .stirred
    @Published var hintedIntent: IntentKind? = nil
    @Published var attachedAssets: [ReferenceAsset] = []
    @Published var parameterOverrides: TechnicalParameterSet = TechnicalParameterSet()
    @Published var manualLocks: [String] = []
    @Published var newLockDraft: String = ""
    @Published var expandWildcardsOnMix: Bool = false

    @Published var customRecipes: [RecipeProfile] = []
    @Published private(set) var wildcardBanks: [WildcardBankRecord] = []
    @Published var wildcardSyncDirectoryPath: String = ""
    @Published var flightSelectedRecipeIDs: Set<String> = [
        "dexdiffusion-flux2-klein-4b",
        "xai-grok-imagine-image-2.0",
        "openai-gpt-image-2",
        "google-gemini-nano-banana-2.1"
    ]

    @Published private(set) var lastParsedIR: CanonicalPromptIR?
    @Published private(set) var lastResult: CompilationResult?
    @Published private(set) var lastFlightReport: FlightComparisonReport?
    @Published private(set) var draftSnapshots: [String] = []
    @Published private(set) var dexDiffusionVersion: DexDiffusionVersionInfo?
    @Published private(set) var dexDiffusionCapabilities: DexDiffusionCapabilitiesSnapshot?
    @Published private(set) var dexDiffusionWildcards: [DexDiffusionWildcardBank] = []
    @Published private(set) var dexDiffusionControlledMaxLength: Int?
    @Published private(set) var readinessMap: [String: ReadinessState] = [:]
    @Published private(set) var apiKeyConfigured: [APIKeyProvider: Bool] = [:]

    @Published var pendingServeConfirmation: PendingServeConfirmation?
    @Published var statusBanner: String = "Offline prompt compiler ready (zero keys required)."
    @Published var lastServeReceipt: String = ""
    @Published var lastImportReport: DexCraftImportReport?
    @Published var isRefreshingCapabilities: Bool = false
    @Published var isSubmittingServe: Bool = false

    init(
        compilerEngine: PromptCompilerEngine = PromptCompilerEngine(),
        flightEngine: FlightEngine = FlightEngine(),
        recipeStore: RecipeStore = RecipeStore(),
        wildcardStore: WildcardStore = WildcardStore(),
        secretStore: SecretStoreProtocol = KeychainSecretStore(),
        dexDiffusionClient: DexDiffusionClient = DexDiffusionClient(),
        importService: DexCraftImportService = DexCraftImportService()
    ) {
        self.compilerEngine = compilerEngine
        self.flightEngine = flightEngine
        self.recipeStore = recipeStore
        self.wildcardStore = wildcardStore
        self.secretStore = secretStore
        self.dexDiffusionClient = dexDiffusionClient
        self.providerRouter = ProviderAPIRouter(secretStore: secretStore)
        self.importService = importService

        self.customRecipes = recipeStore.loadCustomRecipes()
        self.wildcardSyncDirectoryPath = wildcardStore.loadSyncConfig().externalSyncDirectoryPath
        self.wildcardBanks = wildcardStore.loadAllLocalBanks()
        refreshKeychainStatuses(performKeychainRead: false)
        recomputeReadinessMap()
    }

    var allRecipes: [RecipeProfile] {
        compilerEngine.registry.allRecipes(customRecipes: customRecipes)
    }

    var activeRecipe: RecipeProfile {
        compilerEngine.registry.recipe(for: selectedRecipeID, customRecipes: customRecipes)
            ?? compilerEngine.registry.defaultRecipe(for: selectedDestination, customRecipes: customRecipes)
    }

    func availableRecipes(for destination: TargetDestination) -> [RecipeProfile] {
        compilerEngine.registry.recipes(for: destination, customRecipes: customRecipes)
    }

    func readiness(for recipe: RecipeProfile) -> ReadinessState {
        readinessMap[recipe.id] ?? .sourceImplemented
    }

    func mixPrompt(rawInput: String, variables: [String: String], legacyOptions: EnhancementOptions) -> CompilationResult {
        if draftSnapshots.last != rawInput && !rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftSnapshots.append(rawInput)
            if draftSnapshots.count > 25 {
                draftSnapshots.removeFirst(draftSnapshots.count - 25)
            }
        }

        let effectiveInput = expandWildcardsOnMix
            ? wildcardStore.expandTokens(in: rawInput, banks: wildcardBanks)
            : rawInput

        let ir = compilerEngine.parser.parse(
            rawInput: effectiveInput,
            hintedIntent: hintedIntent,
            attachedAssets: attachedAssets,
            parameterOverrides: parameterOverrides,
            manualLocks: manualLocks
        )
        lastParsedIR = ir

        let recipe = activeRecipe
        let compiled = compilerEngine.compile(
            ir: ir,
            recipe: recipe,
            mixMode: mixMode,
            variables: variables,
            legacyOptions: legacyOptions,
            readiness: readiness(for: recipe)
        )
        lastResult = compiled
        statusBanner = "\(recipe.name) · \(compiled.proofReport.summaryBadge) · \(compiled.compilationDurationMs) ms"
        return compiled
    }

    func expandWildcardTokens(in text: String, seed: UInt64? = nil) -> String {
        wildcardStore.expandTokens(in: text, banks: wildcardBanks, seed: seed)
    }

    func setWildcardSyncDirectory(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        var config = wildcardStore.loadSyncConfig()
        config.externalSyncDirectoryPath = trimmed
        wildcardStore.saveSyncConfig(config)
        wildcardSyncDirectoryPath = trimmed
        mergeWildcardCatalog(remoteBanks: dexDiffusionWildcards)
        statusBanner = trimmed.isEmpty
            ? "Cleared external wildcard sync folder."
            : "Synced local wildcards with \(URL(fileURLWithPath: trimmed).lastPathComponent)."
    }

    func loadWildcardBankDetail(name: String) async -> WildcardBankRecord? {
        if let detail = try? await dexDiffusionClient.fetchWildcardDetail(name: name, all: true) {
            let record = WildcardBankRecord(
                name: detail.name,
                items: detail.items,
                description: detail.description,
                tags: detail.tags,
                source: .dexterFusion,
                isFullDetailLoaded: true,
                previewCount: detail.count
            )
            upsertWildcardRecordInMemory(record)
            return record
        }
        return wildcardBanks.first { $0.id == name.lowercased() }
    }

    func saveWildcardBank(name: String, items: [String], description: String, tags: [String]) async {
        do {
            let cleanItems = wildcardStore.sanitizeItems(items)
            let localSaved = try wildcardStore.saveBankLocally(
                name: name,
                items: cleanItems,
                description: description,
                tags: tags,
                source: .localUser,
                mirrorToSyncFolder: true
            )

            var pushedRemote = false
            if (try? await dexDiffusionClient.saveWildcardBank(
                name: localSaved.name,
                items: localSaved.items,
                description: localSaved.description,
                tags: localSaved.tags
            )) != nil {
                pushedRemote = true
            }

            let finalRecord = WildcardBankRecord(
                name: localSaved.name,
                items: localSaved.items,
                description: localSaved.description,
                tags: localSaved.tags,
                source: pushedRemote ? .dexterFusion : .localUser,
                isFullDetailLoaded: true,
                previewCount: localSaved.count
            )
            upsertWildcardRecordInMemory(finalRecord)
            statusBanner = pushedRemote
                ? "Saved & synced wildcard \"\(localSaved.name)\" (\(localSaved.count) items) to Dexter Fusion."
                : "Saved wildcard \"\(localSaved.name)\" (\(localSaved.count) items) locally."
        } catch {
            statusBanner = "Wildcard save failed: \(error.localizedDescription)"
        }
    }

    func deleteWildcardBank(name: String) async {
        wildcardStore.deleteBankLocally(name: name, removeFromSyncFolder: !wildcardSyncDirectoryPath.isEmpty)
        wildcardBanks.removeAll { $0.id == name.lowercased() }

        var removedRemote = false
        if (try? await dexDiffusionClient.deleteWildcardBank(name: name)) != nil {
            removedRemote = true
        }
        mergeWildcardCatalog(remoteBanks: dexDiffusionWildcards)
        statusBanner = removedRemote
            ? "Removed wildcard \"\(name)\" locally & in Dexter Fusion."
            : "Removed local wildcard \"\(name)\"."
    }

    func savePromptQuickly(
        title: String,
        body: String,
        saveToLibrary: Bool,
        saveAsTemplate: Bool,
        into viewModel: PromptEngineViewModel
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle = trimmedTitle.isEmpty ? "Mix — \(activeRecipe.name)" : trimmedTitle
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            statusBanner = "Nothing to save yet."
            return
        }

        if saveToLibrary {
            viewModel.createPromptLibraryPrompt(title: effectiveTitle, body: trimmedBody)
        }
        if saveAsTemplate {
            let previousInput = viewModel.roughInput
            viewModel.roughInput = trimmedBody
            viewModel.templateNameDraft = effectiveTitle
            _ = viewModel.saveCurrentAsTemplate(category: selectedDestination.shortName, tags: [activeRecipe.modelID])
            viewModel.roughInput = previousInput
        }
        statusBanner = "Saved prompt \"\(effectiveTitle)\"."
    }

    private func upsertWildcardRecordInMemory(_ record: WildcardBankRecord) {
        if let idx = wildcardBanks.firstIndex(where: { $0.id == record.id }) {
            wildcardBanks[idx] = record
        } else {
            wildcardBanks.append(record)
        }
        wildcardBanks.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func mergeWildcardCatalog(remoteBanks: [DexDiffusionWildcardBank]) {
        var map: [String: WildcardBankRecord] = [:]
        for local in wildcardStore.loadAllLocalBanks() {
            map[local.id] = local
        }
        for remote in remoteBanks {
            let key = remote.name.lowercased()
            if let existing = map[key], existing.isFullDetailLoaded && !existing.items.isEmpty && existing.count == remote.count {
                // Keep loaded items while updating source badge to Dexter Fusion
                var updated = existing
                updated.source = .dexterFusion
                updated.description = remote.description.isEmpty ? existing.description : remote.description
                updated.tags = remote.tags.isEmpty ? existing.tags : remote.tags
                map[key] = updated
            } else {
                map[key] = WildcardBankRecord(
                    name: remote.name,
                    items: remote.sampleEntries,
                    description: remote.description,
                    tags: remote.tags,
                    source: .dexterFusion,
                    isFullDetailLoaded: false,
                    previewCount: remote.count
                )
            }
        }
        wildcardBanks = map.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func restorePreviousSnapshot() -> String? {
        guard !draftSnapshots.isEmpty else { return nil }
        return draftSnapshots.popLast()
    }

    func compileFlight(rawInput: String, variables: [String: String], legacyOptions: EnhancementOptions) -> FlightComparisonReport {
        let selected = allRecipes.filter { flightSelectedRecipeIDs.contains($0.id) }
        let targets = selected.isEmpty
            ? Array(allRecipes.prefix(4))
            : selected

        let report = flightEngine.compileFlight(
            rawInput: rawInput,
            recipes: targets,
            mixMode: mixMode,
            hintedIntent: hintedIntent,
            attachedAssets: attachedAssets,
            parameterOverrides: parameterOverrides,
            manualLocks: manualLocks,
            variables: variables,
            legacyOptions: legacyOptions,
            readinessLookup: readinessMap
        )
        lastFlightReport = report
        lastParsedIR = report.sourceIR
        statusBanner = "Flight compiled across \(report.entries.count) targets in \(report.totalDurationMs) ms"
        return report
    }

    func addManualLock() {
        let trimmed = newLockDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !manualLocks.contains(trimmed) else { return }
        manualLocks.append(trimmed)
        newLockDraft = ""
    }

    func removeManualLock(_ lock: String) {
        manualLocks.removeAll { $0 == lock }
    }

    func addReferenceAsset(label: String, pathOrURI: String, role: ReferenceAssetRole, notes: String = "") {
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPath = pathOrURI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLabel.isEmpty || !cleanPath.isEmpty else { return }
        attachedAssets.append(
            ReferenceAsset(
                label: cleanLabel.isEmpty ? URL(fileURLWithPath: cleanPath).lastPathComponent : cleanLabel,
                pathOrURI: cleanPath,
                role: role,
                notes: notes
            )
        )
    }

    func removeReferenceAsset(id: UUID) {
        attachedAssets.removeAll { $0.id == id }
    }

    func saveCustomHouseSpecial(name: String, styleSuffix: String, defaultNegative: String, mix: MixMode) {
        let base = activeRecipe
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        let custom = RecipeProfile(
            id: "custom-\(UUID().uuidString.lowercased().prefix(8))",
            version: "1.0.0",
            name: cleanName,
            destination: base.destination,
            modelID: base.modelID,
            subtitle: "Custom House Special based on \(base.modelID)",
            promptDialectNote: base.promptDialectNote,
            defaultMixMode: mix,
            systemPrelude: base.systemPrelude,
            styleSuffix: styleSuffix.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultNegativePrompt: defaultNegative.trimmingCharacters(in: .whitespacesAndNewlines),
            isBuiltIn: false,
            constraints: base.constraints
        )
        customRecipes = recipeStore.upsertCustomRecipe(custom)
        selectedRecipeID = custom.id
        recomputeReadinessMap()
        statusBanner = "Saved House Special recipe \"\(cleanName)\"."
    }

    func deleteCustomHouseSpecial(id: String) {
        customRecipes = recipeStore.deleteCustomRecipe(id: id)
        if selectedRecipeID == id {
            selectedRecipeID = compilerEngine.registry.defaultRecipe(for: selectedDestination).id
        }
        recomputeReadinessMap()
    }

    // MARK: - DexDiffusion Live Status

    func refreshDexDiffusionStatus() async {
        isRefreshingCapabilities = true
        defer { isRefreshingCapabilities = false }

        async let versionTask = try? dexDiffusionClient.fetchVersion()
        async let capsTask = dexDiffusionClient.fetchCapabilities()
        async let wildcardsTask = try? dexDiffusionClient.fetchWildcards()
        async let maxLenTask = dexDiffusionClient.fetchControlledPromptMaxLength()

        dexDiffusionVersion = await versionTask
        dexDiffusionCapabilities = await capsTask
        dexDiffusionWildcards = await wildcardsTask ?? []
        dexDiffusionControlledMaxLength = await maxLenTask
        mergeWildcardCatalog(remoteBanks: dexDiffusionWildcards)
        recomputeReadinessMap()

        if let caps = dexDiffusionCapabilities {
            statusBanner = caps.reachable
                ? "DexDiffusion online (\(caps.targets.count) targets · \(wildcardBanks.count) wildcard banks)"
                : "DexDiffusion offline · \(wildcardBanks.count) built-in/local wildcard banks ready"
        }
    }

    func refreshKeychainStatuses(performKeychainRead: Bool = true) {
        var next: [APIKeyProvider: Bool] = [:]
        for provider in APIKeyProvider.allCases {
            if performKeychainRead {
                next[provider] = secretStore.hasSecret(for: provider)
            } else {
                next[provider] = false
            }
        }
        apiKeyConfigured = next
        recomputeReadinessMap()
    }

    func saveAPIKey(_ value: String, for provider: APIKeyProvider) {
        do {
            try secretStore.saveSecret(value, for: provider)
            apiKeyConfigured[provider] = secretStore.hasSecret(for: provider)
            recomputeReadinessMap()
            statusBanner = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Removed \(provider.displayName) key from Keychain."
                : "Saved \(provider.displayName) key to macOS Keychain."
        } catch {
            statusBanner = "Keychain save failed: \(error.localizedDescription)"
        }
    }

    func deleteAPIKey(for provider: APIKeyProvider) {
        do {
            try secretStore.deleteSecret(for: provider)
            apiKeyConfigured[provider] = false
            recomputeReadinessMap()
            statusBanner = "Removed \(provider.displayName) key from Keychain."
        } catch {
            statusBanner = "Keychain delete failed: \(error.localizedDescription)"
        }
    }

    func recomputeReadinessMap() {
        var next: [String: ReadinessState] = [:]
        let capsByID = Dictionary(
            uniqueKeysWithValues: (dexDiffusionCapabilities?.targets ?? []).map { ($0.id, $0.readinessState) }
        )
        let isDexOnline = dexDiffusionCapabilities?.reachable == true

        for recipe in allRecipes {
            switch recipe.destination {
            case .dexDiffusionImage:
                if let matched = capsByID[recipe.modelID] {
                    next[recipe.id] = matched
                } else if isDexOnline {
                    next[recipe.id] = .blocked(reason: "Not advertised in active worker")
                } else {
                    next[recipe.id] = .sourceImplemented
                }
            case .grokImagineImage, .grokImagineVideo, .openAIImage, .openAITextAgent, .geminiImage, .geminiVideo, .geminiTextAgent:
                if let keyProvider = ProviderAPIRouter.providerKey(for: recipe.destination), apiKeyConfigured[keyProvider] == true {
                    next[recipe.id] = .availableToUser
                } else {
                    next[recipe.id] = .sourceImplemented
                }
            case .claudeTextAgent, .perplexityResearch, .agenticIDEWorkflow:
                next[recipe.id] = .currentlyReady
            }
        }
        readinessMap = next
    }

    // MARK: - Serve Actions (Explicit Safety Gates)

    func copyCompiledPrompt() {
        guard let result = lastResult else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.compiledPrompt, forType: .string)
        statusBanner = "Copied compiled prompt (\(result.compiledPrompt.count) chars) to clipboard."
    }

    func copyPayloadJSON() {
        guard let result = lastResult else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.structuredPayloadJSON, forType: .string)
        statusBanner = "Copied structured \(result.modelID) JSON payload to clipboard."
    }

    func openDexDiffusionStudio() {
        NSWorkspace.shared.open(dexDiffusionClient.studioURL)
        statusBanner = "Opened DexDiffusion Studio in browser."
    }

    func exportFlightMarkdownWithSavePanel() {
        guard let flight = lastFlightReport else { return }
        let markdown = flightEngine.exportFlightMarkdown(flight)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "dex-promptender-flight.md"
        if panel.runModal() == .OK, let url = panel.url {
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
            statusBanner = "Exported Flight comparison to \(url.lastPathComponent)."
        }
    }

    func requestExternalServe(channel: ServeChannel) {
        guard let result = lastResult else {
            statusBanner = "Mix a prompt before serving."
            return
        }
        guard !result.proofReport.hasBlockingIssues else {
            statusBanner = "Resolve blocking Proof issues before external submission."
            return
        }

        switch channel {
        case .submitDexDiffusionControlled:
            pendingServeConfirmation = PendingServeConfirmation(
                channel: channel,
                destinationTitle: "Local DexDiffusion Worker",
                endpointURL: dexDiffusionClient.baseURL.appendingPathComponent("api/actions/generate-controlled").absoluteString,
                modelID: result.modelID,
                redactedHeaders: ["Content-Type": "application/json"],
                payloadPreview: result.structuredPayloadJSON,
                billingNotice: "Local compute worker submission (uses local queue via DexDiffusion). Will write canonical output under DexDiffusion's configured output folder upon completion.",
                result: result
            )
        case .submitAuthorizedProviderAPI:
            do {
                let preview = try providerRouter.buildRedactedRequestPreview(for: result)
                pendingServeConfirmation = PendingServeConfirmation(
                    channel: channel,
                    destinationTitle: result.target.displayName,
                    endpointURL: preview.url,
                    modelID: result.modelID,
                    redactedHeaders: preview.headers,
                    payloadPreview: preview.body,
                    billingNotice: "LIVE CLOUD API REQUEST: Sending this payload will consume API credits / trigger billable generation on your configured Keychain account.",
                    result: result
                )
            } catch {
                statusBanner = error.localizedDescription
            }
        default:
            break
        }
    }

    func confirmAndExecutePendingServe() async {
        guard let pending = pendingServeConfirmation else { return }
        isSubmittingServe = true
        defer {
            isSubmittingServe = false
            pendingServeConfirmation = nil
        }

        let token = ServeAuthorizationToken(channel: pending.channel, targetID: pending.result.modelID)
        do {
            switch pending.channel {
            case .submitDexDiffusionControlled:
                let response = try await dexDiffusionClient.submitControlledGeneration(
                    result: pending.result,
                    authorization: token
                )
                lastServeReceipt = response
                statusBanner = "Submitted to DexDiffusion controlled queue."
            case .submitAuthorizedProviderAPI:
                let receipt = try await providerRouter.submit(
                    result: pending.result,
                    authorization: token
                )
                lastServeReceipt = receipt.responseBody
                statusBanner = "Provider HTTP \(receipt.statusCode) received."
            default:
                break
            }
        } catch {
            lastServeReceipt = error.localizedDescription
            statusBanner = "Serve error: \(error.localizedDescription)"
        }
    }

    func runDexCraftImport(into viewModel: PromptEngineViewModel) {
        do {
            let report = try importService.importLegacyData()
            lastImportReport = report
            statusBanner = report.summaryLine
            // Reload templates/history cleanly via fresh StorageManager read
            let storage = StorageManager()
            let templates = storage.loadTemplates()
            if !templates.isEmpty {
                _ = viewModel.importDefaultTemplates(templates)
            }
        } catch {
            statusBanner = "DexCraft import failed: \(error.localizedDescription)"
        }
    }
}
