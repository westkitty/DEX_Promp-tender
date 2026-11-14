import Foundation

struct FlightEntry: Identifiable, Equatable {
    let id: UUID
    let recipe: RecipeProfile
    let result: CompilationResult

    init(id: UUID = UUID(), recipe: RecipeProfile, result: CompilationResult) {
        self.id = id
        self.recipe = recipe
        self.result = result
    }
}

struct FlightComparisonReport: Equatable {
    let sourceIR: CanonicalPromptIR
    let mixMode: MixMode
    let entries: [FlightEntry]
    let totalDurationMs: Int
}

/// Closed-world parallel target compiler: compiles ONE immutable CanonicalPromptIR
/// independently across multiple models so targets never leak style or parameters into one another.
final class FlightEngine {
    private let compilerEngine: PromptCompilerEngine

    init(compilerEngine: PromptCompilerEngine = PromptCompilerEngine()) {
        self.compilerEngine = compilerEngine
    }

    func compileFlight(
        rawInput: String,
        recipes: [RecipeProfile],
        mixMode: MixMode,
        hintedIntent: IntentKind? = nil,
        attachedAssets: [ReferenceAsset] = [],
        parameterOverrides: TechnicalParameterSet = TechnicalParameterSet(),
        manualLocks: [String] = [],
        variables: [String: String] = [:],
        legacyOptions: EnhancementOptions = EnhancementOptions(),
        readinessLookup: [String: ReadinessState] = [:]
    ) -> FlightComparisonReport {
        let startedAt = Date()
        // Parse ONE immutable CanonicalPromptIR snapshot before fanning out.
        let immutableIR = compilerEngine.parser.parse(
            rawInput: rawInput,
            hintedIntent: hintedIntent,
            attachedAssets: attachedAssets,
            parameterOverrides: parameterOverrides,
            manualLocks: manualLocks
        )

        let entries: [FlightEntry] = recipes.map { recipe in
            let readiness = readinessLookup[recipe.id] ?? .sourceImplemented
            let compiled = compilerEngine.compile(
                ir: immutableIR,
                recipe: recipe,
                mixMode: mixMode,
                variables: variables,
                legacyOptions: legacyOptions,
                readiness: readiness
            )
            return FlightEntry(recipe: recipe, result: compiled)
        }

        let elapsed = max(0, Int(Date().timeIntervalSince(startedAt) * 1000.0))
        return FlightComparisonReport(
            sourceIR: immutableIR,
            mixMode: mixMode,
            entries: entries,
            totalDurationMs: elapsed
        )
    }

    func exportFlightMarkdown(_ report: FlightComparisonReport) -> String {
        var lines: [String] = [
            "# DEX//PROMPTENDER — The Flight Comparison",
            "",
            "- **Intent:** \(report.sourceIR.intentKind.displayName)",
            "- **Mix Mode:** \(report.mixMode.displayName)",
            "- **Targets Compiled:** \(report.entries.count) (Closed-World Isolated)",
            "- **Total Compile Time:** \(report.totalDurationMs) ms",
            "",
            "## Original Draft",
            "```text",
            report.sourceIR.rawInput,
            "```",
            ""
        ]

        for entry in report.entries {
            lines.append("## \(entry.recipe.name) (`\(entry.recipe.modelID)`)")
            lines.append("- **Proof:** \(entry.result.proofReport.summaryBadge)")
            lines.append("- **Readiness:** \(entry.result.readiness.badgeLabel)")
            if !entry.result.recommendedParameters.isEmpty {
                let paramSummary = entry.result.recommendedParameters
                    .sorted(by: { $0.key < $1.key })
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ", ")
                lines.append("- **Parameters:** \(paramSummary)")
            }
            lines.append("")
            lines.append("```text")
            lines.append(entry.result.compiledPrompt)
            lines.append("```")
            if let neg = entry.result.negativePrompt, !neg.isEmpty {
                lines.append("**Negative Prompt:** `\(neg)`")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
