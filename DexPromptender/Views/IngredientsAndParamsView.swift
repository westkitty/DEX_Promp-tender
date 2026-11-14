import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IngredientsAndParamsView: View {
    @ObservedObject var coordinator: PromptenderCoordinator
    @ObservedObject var viewModel: PromptEngineViewModel

    @State private var newAssetLabel: String = ""
    @State private var newAssetPath: String = ""
    @State private var newAssetRole: ReferenceAssetRole = .subject

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            manualLocksSection
            extractedIngredientsSection
            technicalParametersSection
            referenceAssetsSection

            if !coordinator.dexDiffusionWildcards.isEmpty {
                wildcardBankSection
            }
        }
    }

    private var manualLocksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("INVARIANTS & LOCKED SPANS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let ir = coordinator.lastParsedIR {
                    Text("\(ir.invariants.count) enforced")
                        .font(.caption2)
                        .foregroundStyle(.cyan)
                }
            }

            HStack(spacing: 6) {
                TextField("Add exact term or phrase to lock (e.g. exact hex, character name)", text: $coordinator.newLockDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { coordinator.addManualLock() }

                Button("Lock") {
                    coordinator.addManualLock()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(coordinator.newLockDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !coordinator.manualLocks.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(coordinator.manualLocks, id: \.self) { lock in
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                            Text(lock)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Button {
                                coordinator.removeManualLock(lock)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .glassInset(cornerRadius: 6)
                    }
                }
            }

            if let ir = coordinator.lastParsedIR, !ir.lexResult.spans.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-Protected Tokens")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(ir.lexResult.spans) { span in
                                Text("\(span.kind.rawValue): \(span.text)")
                                    .font(.caption2.monospaced())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.cyan.opacity(0.14))
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .glassCard()
    }

    @ViewBuilder
    private var extractedIngredientsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("EXTRACTED INGREDIENTS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let ir = coordinator.lastParsedIR {
                    Text(ir.intentKind.displayName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let ir = coordinator.lastParsedIR {
                let ing = ir.ingredients
                ingredientRow("Subject", value: ing.subject)
                ingredientRow("Scene / Context", value: ing.sceneContext)
                ingredientRow("Style / Medium", value: ing.styleMedium)
                ingredientRow("Camera / Framing", value: ing.cameraComposition)
                ingredientRow("Lighting", value: ing.lightingAtmosphere)
                if !ing.spatialRelations.isEmpty {
                    ingredientRow("Spatial", value: ing.spatialRelations.joined(separator: " | "))
                }
                if !ing.negativeIntent.isEmpty {
                    ingredientRow("Exclusions", value: ing.negativeIntent.joined(separator: ", "))
                }
                if !ing.audioDialogue.isEmpty {
                    ingredientRow(
                        "Audio / Dialogue",
                        value: ([ing.audioDialogue.ambientAudio] + ing.audioDialogue.spokenDialogue + ing.audioDialogue.soundEffects)
                            .filter { !$0.isEmpty }
                            .joined(separator: " | ")
                    )
                }
                if !ing.temporalTimeline.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Video Timeline (\(ing.temporalTimeline.count) beats)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(ing.temporalTimeline) { beat in
                            Text("\(beat.timecodeLabel): \(beat.visualAction)")
                                .font(.caption2)
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(6)
                    .glassInset(cornerRadius: 6)
                }
            } else {
                Text("Click Mix Prompt to parse and inspect ingredients, protected tokens, and timeline structure.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .glassCard()
    }

    private func ingredientRow(_ label: String, value: String) -> some View {
        Group {
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.caption2)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .glassInset(cornerRadius: 6)
            }
        }
    }

    private var technicalParametersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TECHNICAL PARAMETERS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                paramPicker("Aspect", selection: binding(
                    get: { coordinator.parameterOverrides.aspectRatio ?? "Auto" },
                    set: { coordinator.parameterOverrides.aspectRatio = ($0 == "Auto" ? nil : $0) }
                ), options: ["Auto", "1:1", "16:9", "9:16", "4:3", "3:4", "3:2", "2:3", "21:9"])

                paramPicker("Resolution", selection: binding(
                    get: { coordinator.parameterOverrides.resolutionTier ?? "Auto" },
                    set: { coordinator.parameterOverrides.resolutionTier = ($0 == "Auto" ? nil : $0) }
                ), options: ["Auto", "480p", "720p", "1080p", "1K", "2K", "4K", "1024x1024", "1536x1024"])

                paramPicker("Quality", selection: binding(
                    get: { coordinator.parameterOverrides.qualityTier ?? "Auto" },
                    set: { coordinator.parameterOverrides.qualityTier = ($0 == "Auto" ? nil : $0) }
                ), options: ["Auto", "low", "medium", "high", "hd"])
            }

            HStack(spacing: 8) {
                paramPicker("Fidelity", selection: binding(
                    get: { coordinator.parameterOverrides.inputFidelity ?? "Auto" },
                    set: { coordinator.parameterOverrides.inputFidelity = ($0 == "Auto" ? nil : $0) }
                ), options: ["Auto", "low", "high"])

                paramPicker("Background", selection: binding(
                    get: { coordinator.parameterOverrides.backgroundMode ?? "Auto" },
                    set: { coordinator.parameterOverrides.backgroundMode = ($0 == "Auto" ? nil : $0) }
                ), options: ["Auto", "opaque", "transparent"])

                paramPicker("Duration", selection: binding(
                    get: {
                        if let dur = coordinator.parameterOverrides.durationSeconds {
                            return "\(Int(dur))s"
                        }
                        return "Auto"
                    },
                    set: {
                        if $0 == "Auto" {
                            coordinator.parameterOverrides.durationSeconds = nil
                        } else {
                            coordinator.parameterOverrides.durationSeconds = Double($0.replacingOccurrences(of: "s", with: ""))
                        }
                    }
                ), options: ["Auto", "4s", "5s", "6s", "8s", "10s", "12s", "15s"])
            }

            if coordinator.selectedDestination.isTextOrAgentTarget {
                HStack(spacing: 8) {
                    paramPicker("Reasoning", selection: binding(
                        get: { coordinator.parameterOverrides.reasoningEffort ?? "Auto" },
                        set: { coordinator.parameterOverrides.reasoningEffort = ($0 == "Auto" ? nil : $0) }
                    ), options: ["Auto", "low", "medium", "high", "xhigh"])

                    paramPicker("Thinking", selection: binding(
                        get: { coordinator.parameterOverrides.thinkingLevel ?? "Auto" },
                        set: { coordinator.parameterOverrides.thinkingLevel = ($0 == "Auto" ? nil : $0) }
                    ), options: ["Auto", "minimal", "medium", "high"])
                }
            }
        }
        .padding(10)
        .glassCard()
    }

    private func paramPicker(_ title: String, selection: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { opt in
                    Text(opt).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func binding(get: @escaping () -> String, set: @escaping (String) -> Void) -> Binding<String> {
        Binding(get: get, set: set)
    }

    private var referenceAssetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REFERENCE ASSETS & EDIT INPUTS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                TextField("Label (e.g. Hero Frame)", text: $newAssetLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                Picker("Role", selection: $newAssetRole) {
                    ForEach(ReferenceAssetRole.allCases) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 110)

                Button("Browse") {
                    browseReferenceFile()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Add") {
                    coordinator.addReferenceAsset(label: newAssetLabel, pathOrURI: newAssetPath, role: newAssetRole)
                    newAssetLabel = ""
                    newAssetPath = ""
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newAssetLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                          newAssetPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !newAssetPath.isEmpty {
                Text(newAssetPath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ForEach(coordinator.attachedAssets) { asset in
                HStack(spacing: 8) {
                    Text(asset.role.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.cyan)
                    Text(asset.label)
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        coordinator.removeReferenceAsset(id: asset.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .glassInset(cornerRadius: 6)
            }
        }
        .padding(10)
        .glassCard()
    }

    private var wildcardBankSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LIVE DEXDIFFUSION WILDCARD BANKS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(coordinator.dexDiffusionWildcards) { bank in
                        Button("__\(bank.name)__ (\(bank.count))") {
                            let sep = viewModel.roughInput.isEmpty || viewModel.roughInput.hasSuffix(" ") ? "" : ", "
                            viewModel.roughInput += "\(sep)__\(bank.name)__"
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(10)
        .glassCard()
    }

    private func browseReferenceFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .movie, .audio]
        if panel.runModal() == .OK, let url = panel.url {
            newAssetPath = url.path
            if newAssetLabel.isEmpty {
                newAssetLabel = url.deletingPathExtension().lastPathComponent
            }
        }
    }
}
