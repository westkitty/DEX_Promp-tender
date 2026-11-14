import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HouseSpecialsView: View {
    @ObservedObject var coordinator: PromptenderCoordinator
    @ObservedObject var viewModel: PromptEngineViewModel

    @State private var recipeName: String = ""
    @State private var styleSuffix: String = ""
    @State private var defaultNegative: String = ""
    @State private var customMix: MixMode = .stirred

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text("CREATE HOUSE SPECIAL RECIPE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("Saves a reusable preset bound to \(coordinator.activeRecipe.destination.displayName) (\(coordinator.activeRecipe.modelID)).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                TextField("Recipe Name (e.g. Moody 35mm Neon Portrait)", text: $recipeName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                TextField("Style / Formatting Suffix (optional)", text: $styleSuffix)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                TextField("Default Negative Constraints (optional)", text: $defaultNegative)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                HStack {
                    Picker("Default Mix", selection: $customMix) {
                        ForEach(MixMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 210)

                    Spacer()

                    Button("Save House Special") {
                        coordinator.saveCustomHouseSpecial(
                            name: recipeName,
                            styleSuffix: styleSuffix,
                            defaultNegative: defaultNegative,
                            mix: customMix
                        )
                        recipeName = ""
                        styleSuffix = ""
                        defaultNegative = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(recipeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(10)
            .glassCard()

            VStack(alignment: .leading, spacing: 8) {
                Text("SAVED HOUSE SPECIALS (\(coordinator.customRecipes.count))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                if coordinator.customRecipes.isEmpty {
                    Text("No custom House Specials saved yet.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(coordinator.customRecipes) { recipe in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recipe.name)
                                    .font(.caption.weight(.semibold))
                                Text("\(recipe.destination.shortName) · \(recipe.modelID) · \(recipe.defaultMixMode.displayName)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Use & Mix") {
                                coordinator.selectedDestination = recipe.destination
                                coordinator.selectedRecipeID = recipe.id
                                coordinator.mixMode = recipe.defaultMixMode
                                _ = coordinator.mixPrompt(
                                    rawInput: viewModel.roughInput,
                                    variables: viewModel.variableValues,
                                    legacyOptions: viewModel.options
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                coordinator.deleteCustomHouseSpecial(id: recipe.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .glassInset(cornerRadius: 8)
                    }
                }
            }
            .padding(10)
            .glassCard()
        }
    }
}

struct TheCellarView: View {
    @ObservedObject var viewModel: PromptEngineViewModel
    @ObservedObject var coordinator: PromptenderCoordinator

    @State private var cellarSection: CellarSection = .library
    @State private var isHistorySheetPresented: Bool = false

    enum CellarSection: String, CaseIterable, Identifiable {
        case library = "Library"
        case templates = "Templates"
        case history = "History"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Cellar", selection: $cellarSection) {
                    ForEach(CellarSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)

                Button("Local Chat") {
                    viewModel.requestLocalChatWindowToggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            switch cellarSection {
            case .library:
                PromptLibraryTab(viewModel: viewModel)
            case .templates:
                TemplateManagerPanel(viewModel: viewModel)
                    .padding(10)
                    .glassCard()
            case .history:
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("History: \(viewModel.history.count) entries")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Full History") {
                            isHistorySheetPresented = true
                        }
                        .buttonStyle(.bordered)
                    }

                    ForEach(Array(viewModel.history.prefix(6))) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.target.segmentTitle)
                                    .font(.caption.weight(.semibold))
                                Text(entry.originalInput)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Load") {
                                viewModel.loadHistoryEntry(entry)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        .padding(6)
                        .glassInset(cornerRadius: 6)
                    }
                }
                .padding(10)
                .glassCard()
            }
        }
        .sheet(isPresented: $isHistorySheetPresented) {
            HistoryManagerSheet(viewModel: viewModel)
        }
    }
}

struct PromptenderSettingsView: View {
    @ObservedObject var coordinator: PromptenderCoordinator
    @ObservedObject var viewModel: PromptEngineViewModel
    @ObservedObject var appearance: AppearanceSettingsStore

    @State private var xaiKeyDraft: String = ""
    @State private var openAIKeyDraft: String = ""
    @State private var geminiKeyDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            appearanceCard
            dexDiffusionCard
            keychainAPIKeysCard
            dexCraftMigrationCard
            localGGUFCard
        }
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("APPEARANCE · WATERMARK & BACKGROUND IMAGES")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") {
                    appearance.resetToDefaults()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            Toggle("Show Center Watermark", isOn: $appearance.settings.isWatermarkEnabled)
                .font(.caption2)

            if appearance.settings.isWatermarkEnabled {
                HStack(spacing: 6) {
                    TextField("Built-in DexCraftWatermark (or choose image)", text: $appearance.settings.customWatermarkPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption2)
                    Button("Choose...") {
                        if let path = browseImageFile(title: "Choose Watermark Image") {
                            appearance.settings.customWatermarkPath = path
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    if !appearance.settings.customWatermarkPath.isEmpty {
                        Button("Default") {
                            appearance.settings.customWatermarkPath = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }

                HStack {
                    Text("Watermark Opacity (\(Int(appearance.settings.watermarkOpacity * 100))%)")
                        .font(.caption2)
                        .frame(width: 155, alignment: .leading)
                    Slider(value: $appearance.settings.watermarkOpacity, in: 0.0...1.0)
                }

                HStack {
                    Text("Watermark Size (\(String(format: "%.2fx", appearance.settings.watermarkScale)))")
                        .font(.caption2)
                        .frame(width: 155, alignment: .leading)
                    Slider(value: $appearance.settings.watermarkScale, in: 0.3...2.0)
                }

                HStack {
                    Text("Watermark Blend")
                        .font(.caption2)
                        .frame(width: 155, alignment: .leading)
                    Picker("Blend", selection: $appearance.settings.watermarkBlendMode) {
                        ForEach(WatermarkBlendOption.allCases) { opt in
                            Text(opt.displayName).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }

            Divider()

            Toggle("Show Custom Image Behind Glass", isOn: $appearance.settings.isBackdropImageEnabled)
                .font(.caption2)

            if appearance.settings.isBackdropImageEnabled {
                HStack(spacing: 6) {
                    TextField("Select behind-glass background image...", text: $appearance.settings.customBackdropImagePath)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption2)
                    Button("Choose...") {
                        if let path = browseImageFile(title: "Choose Behind-Window Image") {
                            appearance.settings.customBackdropImagePath = path
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                HStack {
                    Text("Behind Image Opacity (\(Int(appearance.settings.backdropOpacity * 100))%)")
                        .font(.caption2)
                        .frame(width: 155, alignment: .leading)
                    Slider(value: $appearance.settings.backdropOpacity, in: 0.0...1.0)
                }

                HStack {
                    Text("Behind Image Blur (\(Int(appearance.settings.backdropBlur))px)")
                        .font(.caption2)
                        .frame(width: 155, alignment: .leading)
                    Slider(value: $appearance.settings.backdropBlur, in: 0.0...28.0)
                }

                HStack {
                    Text("Image Scaling")
                        .font(.caption2)
                        .frame(width: 155, alignment: .leading)
                    Picker("Scaling", selection: $appearance.settings.backdropContentMode) {
                        ForEach(BackdropContentMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            HStack {
                Text("Glass Highlight Tint (\(Int(appearance.settings.glassTintOpacity * 100))%)")
                    .font(.caption2)
                    .frame(width: 155, alignment: .leading)
                Slider(value: $appearance.settings.glassTintOpacity, in: 0.0...0.55)
            }
        }
        .padding(10)
        .glassCard()
    }

    private func browseImageFile(title: String) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff, .webP, .heic]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    private var dexDiffusionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DEXDIFFUSION LIVE INTEGRATION")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(coordinator.isRefreshingCapabilities ? "Probing..." : "Refresh Capabilities") {
                    Task { await coordinator.refreshDexDiffusionStatus() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(coordinator.isRefreshingCapabilities)
            }

            if let ver = coordinator.dexDiffusionVersion {
                Text("Worker version: \(ver.version) · Schema max length: \(coordinator.dexDiffusionControlledMaxLength ?? 4000)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.mint)
            } else {
                Text("Offline / Not probed yet. Prompt compilation requires zero network or running worker.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let caps = coordinator.dexDiffusionCapabilities, !caps.targets.isEmpty {
                ForEach(caps.targets) { target in
                    HStack {
                        Text("\(target.family) · \(target.engine)")
                            .font(.caption2.weight(.medium))
                        Text("(\(target.id))")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                        ReadinessBadge(state: target.readinessState)
                    }
                    .padding(6)
                    .glassInset(cornerRadius: 6)
                }
            }
        }
        .padding(10)
        .glassCard()
    }

    private var keychainAPIKeysCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("OPTIONAL PROVIDER API KEYS (macOS KEYCHAIN)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Check Keychain") {
                    coordinator.refreshKeychainStatuses(performKeychainRead: true)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            Text("Keys are stored exclusively in macOS Keychain (never in code or logs). Zero keys are needed for compiling prompts.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            keyRow(provider: .xai, draft: $xaiKeyDraft)
            keyRow(provider: .openAI, draft: $openAIKeyDraft)
            keyRow(provider: .gemini, draft: $geminiKeyDraft)
        }
        .padding(10)
        .glassCard()
    }

    private func keyRow(provider: APIKeyProvider, draft: Binding<String>) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(provider.displayName)
                    .font(.caption2.weight(.semibold))
                Text(coordinator.apiKeyConfigured[provider] == true ? "Stored in Keychain" : "Not configured")
                    .font(.caption2)
                    .foregroundStyle(coordinator.apiKeyConfigured[provider] == true ? .green : .secondary)
            }
            .frame(width: 170, alignment: .leading)

            SecureField("Paste API Key", text: draft)
                .textFieldStyle(.roundedBorder)
                .font(.caption2)

            Button("Save") {
                coordinator.saveAPIKey(draft.wrappedValue, for: provider)
                draft.wrappedValue = ""
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if coordinator.apiKeyConfigured[provider] == true {
                Button("Clear") {
                    coordinator.deleteAPIKey(for: provider)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var dexCraftMigrationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NON-DESTRUCTIVE DEXCRAFT IMPORT")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Import from DexCraft") {
                    coordinator.runDexCraftImport(into: viewModel)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Text("Copies existing templates & prompt history from ~/Library/Application Support/DexCraft into isolated DexPromptender storage with automatic pre-import backup. Source DexCraft files are never modified.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let report = coordinator.lastImportReport {
                Text(report.summaryLine)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.cyan)
            }
        }
        .padding(10)
        .glassCard()
    }

    private var localGGUFCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OPTIONAL LOCAL GGUF ENHANCEMENT")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack {
                Text("Tiny Model: \(viewModel.embeddedTinyModelIdentifier)")
                    .font(.caption2)
                Spacer()
                Button(viewModel.isEmbeddedTinyModelEnabled ? "Disable" : "Enable") {
                    viewModel.toggleEmbeddedTinyModelEnabled()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            HStack(spacing: 6) {
                TextField("/path/to/model.gguf", text: Binding(
                    get: { viewModel.embeddedTinyModelPath },
                    set: { viewModel.updateEmbeddedTinyModelPath($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.caption2)

                Button("Browse") {
                    viewModel.browseEmbeddedTinyModelPath()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .glassCard()
    }
}
