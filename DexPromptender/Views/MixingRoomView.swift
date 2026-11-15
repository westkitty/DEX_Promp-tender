import AppKit
import SwiftUI

enum PromptenderWorkspaceSection: String, CaseIterable, Identifiable {
    case bar = "Mix"
    case wildcards = "Wildcards"
    case ingredients = "Ingredients"
    case flight = "Flight"
    case specials = "Specials"
    case cellar = "Cellar"
    case settings = "Settings"

    var id: String { rawValue }
}

enum CompiledOutputTab: String, CaseIterable, Identifiable {
    case compiled = "Compiled"
    case payload = "Payload JSON"
    case proof = "Proof"
    case diff = "Semantic Diff"

    var id: String { rawValue }
}

struct MixingRoomView: View {
    @ObservedObject var viewModel: PromptEngineViewModel
    @ObservedObject var coordinator: PromptenderCoordinator
    @ObservedObject var appearance: AppearanceSettingsStore
    let isDetached: Bool
    let availableWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var resultIsCurrent: Bool {
        coordinator.isLastResultCurrent(
            rawInput: viewModel.roughInput,
            variables: viewModel.variableValues,
            legacyOptions: viewModel.options
        )
    }

    @State private var activeSection: PromptenderWorkspaceSection = .bar
    @State private var outputTab: CompiledOutputTab = .compiled
    @State private var isSavePromptPopoverShown: Bool = false
    @State private var savePromptTitle: String = ""
    @State private var saveCompiledCopy: Bool = true
    @State private var alsoSaveAsTemplate: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()
                .overlay(Color.white.opacity(0.14))

            sectionNavigationBar

            if isDetached && availableWidth >= 820 {
                detachedMixingRoomBody
            } else {
                compactBarBody
            }

            statusFooterBar
        }
        .sheet(item: $coordinator.pendingServeConfirmation) { confirmation in
            ServeConfirmationSheet(
                coordinator: coordinator, confirmation: confirmation,
                viewModel: viewModel
            )
        }
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "wineglass.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.cyan)

            VStack(alignment: .leading, spacing: 1) {
                Text("DEX//PROMPTENDER")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(0.8)
                Text("Your intent. Perfectly served.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                performMixPrompt()
            } label: {
                Label("Mix Prompt", systemImage: "wand.and.stars")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.roughInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !isDetached {
                Button {
                    viewModel.isResultPanelVisible.toggle()
                } label: {
                    Image(systemName: viewModel.isResultPanelVisible ? "sidebar.right" : "rectangle.split.2x1")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(minWidth: 44, minHeight: 44)
                .help(viewModel.isResultPanelVisible ? "Collapse Result Drawer" : "Show Compiled Output")
                .accessibilityLabel(
                    viewModel.isResultPanelVisible ? "Hide compiled output" : "Show compiled output"
                )
                .accessibilityHint("Toggles the compiled-output panel")
            }

            Button {
                viewModel.requestDetachedWindowToggle()
            } label: {
                Image(systemName: isDetached ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(minWidth: 44, minHeight: 44)
            .help(isDetached ? "Return to Menu Bar" : "Open Detached Mixing Room")
            .accessibilityLabel(
                isDetached ? "Return to menu bar" : "Open detached Mixing Room"
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var sectionNavigationBar: some View {
        Group {
            if !isDetached || availableWidth < 760 {
                HStack {
                    Menu {
                        ForEach(PromptenderWorkspaceSection.allCases) { section in
                            Button {
                                activeSection = section
                            } label: {
                                if activeSection == section {
                                    Label(section.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(section.rawValue)
                                }
                            }
                        }
                    } label: {
                        Label(activeSection.rawValue, systemImage: "square.grid.2x2")
                    }
                    .accessibilityLabel("Workspace section")
                    .accessibilityValue(activeSection.rawValue)
                    Spacer()
                    Text(activeSection == .bar ? "Draft and compile" : activeSection.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(PromptenderWorkspaceSection.allCases) { section in
                        let isSelected = activeSection == section
                        Button {
                            activeSection = section
                        } label: {
                            Text(section.rawValue)
                                .font(.caption.weight(isSelected ? .semibold : .regular))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? Color.accentColor.opacity(0.22) : .clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(section.rawValue)
                        .accessibilityValue(isSelected ? "Selected" : "Not selected")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var detachedMixingRoomBody: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    leftColumnContent
                }
                .padding(12)
            }
            .frame(minWidth: 380, idealWidth: 460, maxWidth: 560)

            Divider()
                .overlay(Color.white.opacity(0.14))

            compiledOutputPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var compactBarBody: some View {
        if availableWidth >= 820 {
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        leftColumnContent
                    }
                    .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if viewModel.isResultPanelVisible {
                    Divider()
                    compiledOutputPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                }
            }
        } else if viewModel.isResultPanelVisible {
            compiledOutputPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    leftColumnContent
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var leftColumnContent: some View {
        switch activeSection {
        case .bar:
            TargetReadinessAndMixControlsView(coordinator: coordinator, compact: !isDetached)
            rawInputEditorCard
            if !viewModel.detectedVariables.isEmpty {
                variablesCard
            }
        case .wildcards:
            WildcardsStudioView(coordinator: coordinator, viewModel: viewModel)
        case .ingredients:
            IngredientsAndParamsView(coordinator: coordinator, viewModel: viewModel)
        case .flight:
            FlightComparisonView(coordinator: coordinator, viewModel: viewModel)
        case .specials:
            HouseSpecialsView(coordinator: coordinator, viewModel: viewModel)
        case .cellar:
            TheCellarView(viewModel: viewModel, coordinator: coordinator)
        case .settings:
            PromptenderSettingsView(coordinator: coordinator, viewModel: viewModel, appearance: appearance)
        }
    }

    private var rawInputEditorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RAW INTENT & INGREDIENTS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.roughInput.contains("__") {
                    Button("Roll Wildcards") {
                        viewModel.roughInput = coordinator.expandWildcardTokens(in: viewModel.roughInput)
                        coordinator.statusBanner = "Expanded __wildcard__ tokens in draft."
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                if !coordinator.draftSnapshots.isEmpty {
                    Button("Revert Draft") {
                        if let prior = coordinator.restorePreviousSnapshot() {
                            viewModel.roughInput = prior
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                Button("Save...") {
                    savePromptTitle = ""
                    isSavePromptPopoverShown = true
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(viewModel.roughInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && coordinator.lastResult == nil)
                .popover(isPresented: $isSavePromptPopoverShown) {
                    savePromptPopoverContent
                }
                Button("Clear") {
                    viewModel.roughInput = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(viewModel.roughInput.isEmpty)
            }

            ZStack(alignment: .topLeading) {
                TransparentTextEditor(text: $viewModel.roughInput)
                    .frame(minHeight: isDetached ? 180 : 150)

                if viewModel.roughInput.isEmpty {
                    Text("Describe what you want to create, paste timeline beats (0s-4s), lock exact phrases with lock:\"text\", specify counts (\"three red apples\"), exclusions (--no blur), or coding instructions...")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.8))
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
            .padding(6)
            .glassInset(cornerRadius: 8)

            HStack(spacing: 8) {
                Text("\(viewModel.roughInput.count) chars")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Flight Compare") {
                    _ = coordinator.compileFlight(
                        rawInput: viewModel.roughInput,
                        variables: viewModel.variableValues,
                        legacyOptions: viewModel.options
                    )
                    activeSection = .flight
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.roughInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Mix Prompt") {
                    performMixPrompt()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.roughInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
        .glassCard()
    }

    private var variablesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TEMPLATE VARIABLES")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(viewModel.detectedVariables, id: \.self) { variableName in
                HStack(spacing: 8) {
                    Text("{\(variableName)}")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.cyan)
                        .frame(width: 110, alignment: .leading)
                    TextField("Value for \(variableName)", text: viewModel.bindingForVariable(variableName))
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }
            }
        }
        .padding(10)
        .glassCard()
    }

    private var compiledOutputPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Picker("Output", selection: $outputTab) {
                    ForEach(CompiledOutputTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if let result = coordinator.lastResult {
                if !resultIsCurrent {
                    HStack(spacing: 8) {
                        Label("Output out of date", systemImage: "arrow.clockwise.circle")
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Button("Mix Updated Draft") { performMixPrompt() }
                            .buttonStyle(.borderedProminent)
                    }
                    Text("Your draft, recipe, settings, references, or wildcards changed. Mix again before copying or serving.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(result.modelID)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    ReadinessBadge(state: result.readiness)
                    Text(result.proofReport.summaryBadge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(result.proofReport.hasBlockingIssues ? .red : (result.proofReport.warningCount > 0 ? .orange : .green))
                }

                ScrollView {
                    switch outputTab {
                    case .compiled:
                        compiledPromptView(result)
                    case .payload:
                        APIPayloadView(result: result) {
                            coordinator.copyPayloadJSON(
                                rawInput: viewModel.roughInput,
                                variables: viewModel.variableValues,
                                legacyOptions: viewModel.options
                            )
                        }
                    case .proof:
                        ProofReportView(report: result.proofReport)
                    case .diff:
                        SemanticDiffView(diff: result.semanticDiff, provenance: result.provenance)
                    }
                }

                serveBar(result: result)
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Ready to Compile")
                        .font(.headline)
                    Text("Choose a Target Recipe and Mix Mode on the left, then click Mix Prompt (Cmd+Return).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(12)
    }

    private func compiledPromptView(_ result: CompilationResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let system = result.systemInstructions, !system.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SYSTEM / ROLE INSTRUCTIONS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(system)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassInset(cornerRadius: 8)
                }
                .padding(10)
                .glassCard()
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("COMPILED PROMPT")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(result.compiledPrompt.count) chars · \(result.mixMode.displayName)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(result.compiledPrompt)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassInset(cornerRadius: 8)
            }
            .padding(10)
            .glassCard()

            if let negative = result.negativePrompt, !negative.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEGATIVE PROMPT / EXCLUSIONS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(negative)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassInset(cornerRadius: 8)
                }
                .padding(10)
                .glassCard()
            }

            if !coordinator.lastServeReceipt.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LAST EXTERNAL SERVE RECEIPT")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.mint)
                    Text(coordinator.lastServeReceipt)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassInset(cornerRadius: 8)
                }
                .padding(10)
                .glassCard()
            }
        }
    }

    private func serveBar(result: CompilationResult) -> some View {
        HStack(spacing: 8) {
            Button("Copy Prompt") {
                coordinator.copyCompiledPrompt(
                    rawInput: viewModel.roughInput,
                    variables: viewModel.variableValues,
                    legacyOptions: viewModel.options
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!resultIsCurrent)

            Button("Copy JSON") {
                coordinator.copyPayloadJSON(
                    rawInput: viewModel.roughInput,
                    variables: viewModel.variableValues,
                    legacyOptions: viewModel.options
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!resultIsCurrent)

            Button("Save Prompt...") {
                savePromptTitle = ""
                isSavePromptPopoverShown = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Menu("Serve") {
                Button("Open DexDiffusion Studio (Browser)") {
                    coordinator.openDexDiffusionStudio()
                }

                Divider()

                Button("Submit to Local DexDiffusion Worker...") {
                    coordinator.requestExternalServe(
                        channel: .submitDexDiffusionControlled,
                        rawInput: viewModel.roughInput,
                        variables: viewModel.variableValues,
                        legacyOptions: viewModel.options
                    )
                }
                .disabled(!resultIsCurrent || result.target != .dexDiffusionImage || result.proofReport.hasBlockingIssues)

                Button("Submit to Authorized Provider API...") {
                    coordinator.requestExternalServe(
                        channel: .submitAuthorizedProviderAPI,
                        rawInput: viewModel.roughInput,
                        variables: viewModel.variableValues,
                        legacyOptions: viewModel.options
                    )
                }
                .disabled(!resultIsCurrent || ProviderAPIRouter.providerKey(for: result.target) == nil || result.proofReport.hasBlockingIssues)
            }
            .menuStyle(.borderedButton)
            .controlSize(.small)
        }
        .padding(.top, 4)
    }

    private var statusFooterBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(coordinator.dexDiffusionCapabilities?.reachable == true ? Color.green : Color.cyan)
                .frame(width: 6, height: 6)
            Text(coordinator.statusBanner)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityLabel("Status: \(coordinator.statusBanner)")
            Spacer()
            Text("v\(coordinator.activeRecipe.version) · Offline-First")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.18))
    }

    private func performMixPrompt() {
        let result = coordinator.mixPrompt(
            rawInput: viewModel.roughInput,
            variables: viewModel.variableValues,
            legacyOptions: viewModel.options
        )
        viewModel.generatedPrompt = result.compiledPrompt
        viewModel.recordCompiledMixHistory(
            target: result.target,
            originalInput: viewModel.roughInput,
            compiledPrompt: result.compiledPrompt
        )
        viewModel.isResultPanelVisible = true
    }

    private var savePromptPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SAVE PROMPT")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Prompt Title (e.g. Moody Samurai Neon)", text: $savePromptTitle)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            if coordinator.lastResult != nil {
                Picker("Content", selection: $saveCompiledCopy) {
                    Text("Compiled Output").tag(true)
                    Text("Raw Draft").tag(false)
                }
                .pickerStyle(.segmented)
            }

            Toggle("Also save as reusable Template", isOn: $alsoSaveAsTemplate)
                .font(.caption2)

            HStack {
                Button("Cancel") {
                    isSavePromptPopoverShown = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Save to Cellar") {
                    let body: String
                    if saveCompiledCopy, let compiled = coordinator.lastResult?.compiledPrompt, !compiled.isEmpty {
                        body = compiled
                    } else {
                        body = viewModel.roughInput
                    }
                    coordinator.savePromptQuickly(
                        title: savePromptTitle,
                        body: body,
                        saveToLibrary: true,
                        saveAsTemplate: alsoSaveAsTemplate,
                        into: viewModel
                    )
                    isSavePromptPopoverShown = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
