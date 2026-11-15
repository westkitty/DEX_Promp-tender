import AppKit
import SwiftUI

struct FlightComparisonView: View {
    @ObservedObject var coordinator: PromptenderCoordinator
    @ObservedObject var viewModel: PromptEngineViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerControls
            recipeSelectorGrid

            if let report = coordinator.lastFlightReport {
                HStack {
                    Text("Compiled \(report.entries.count) targets from single Canonical IR (\(report.totalDurationMs) ms)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Export Markdown...") {
                        coordinator.exportFlightMarkdownWithSavePanel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(report.entries) { entry in
                            flightCard(entry)
                        }
                    }
                }
            } else {
                Text("Select 2 or more target models above and click Compile Flight to compare identical intent compiled cleanly for each model dialect.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
            }
        }
    }

    private var headerControls: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("THE FLIGHT · MULTI-TARGET COMPILER")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Zero cross-target leakage: each recipe compiles independently from one Canonical IR.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Compile Flight (\(coordinator.flightSelectedRecipeIDs.count))") {
                _ = coordinator.compileFlight(
                    rawInput: viewModel.roughInput,
                    variables: viewModel.variableValues,
                    legacyOptions: viewModel.options
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(viewModel.roughInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(10)
        .glassCard()
    }

    private var recipeSelectorGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Flight Targets")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Select Core 4") {
                    coordinator.flightSelectedRecipeIDs = [
                        "dexdiffusion-flux2-klein-4b",
                        "xai-grok-imagine-image-2.0",
                        "openai-gpt-image-2",
                        "google-gemini-nano-banana-2.1"
                    ]
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                Button("Select All 8 Families") {
                    coordinator.flightSelectedRecipeIDs = [
                        "dexdiffusion-flux2-klein-4b",
                        "xai-grok-imagine-image-2.0",
                        "xai-grok-imagine-video-1.5",
                        "openai-gpt-image-2",
                        "openai-gpt-6.1-sol-responses",
                        "google-gemini-nano-banana-2.1",
                        "google-gemini-omni-1.2-flash",
                        "google-gemini-3.1-pro"
                    ]
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(coordinator.allRecipes) { recipe in
                    let isSelected = coordinator.flightSelectedRecipeIDs.contains(recipe.id)
                    Button {
                        if isSelected {
                            coordinator.flightSelectedRecipeIDs.remove(recipe.id)
                        } else {
                            coordinator.flightSelectedRecipeIDs.insert(recipe.id)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                .font(.caption2)
                                .foregroundStyle(isSelected ? .cyan : .secondary)
                            Text(recipe.name)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(isSelected ? Color.cyan.opacity(0.14) : Color.clear)
                        .glassInset(cornerRadius: 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(recipe.name)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .padding(10)
        .glassCard()
    }

    private func flightCard(_ entry: FlightEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(entry.recipe.name)
                    .font(.caption.weight(.semibold))
                Text(entry.recipe.modelID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                ReadinessBadge(state: entry.result.readiness)
                Text(entry.result.proofReport.summaryBadge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(entry.result.proofReport.hasBlockingIssues ? .red : .green)
            }

            Text(entry.result.compiledPrompt)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .glassInset(cornerRadius: 6)

            DisclosureGroup("Full compiled prompt") {
                Text(entry.result.compiledPrompt)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let neg = entry.result.negativePrompt, !neg.isEmpty {
                Text("Negative: \(neg)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button("Copy Prompt") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.result.compiledPrompt, forType: .string)
                    coordinator.statusBanner = "Copied \(entry.recipe.name) prompt to clipboard."
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Focus Target") {
                    coordinator.selectedDestination = entry.recipe.destination
                    coordinator.selectedRecipeID = entry.recipe.id
                    _ = coordinator.mixPrompt(
                        rawInput: viewModel.roughInput,
                        variables: viewModel.variableValues,
                        legacyOptions: viewModel.options
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
                Text("\(entry.result.proofReport.characterCount) chars")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .glassCard()
    }
}
