import Foundation

/// Preserves DexCraft's battle-tested Claude XML, Perplexity Verification, and Agentic IDE compilers
/// inside the new MixMode + CanonicalPromptIR + Strain architecture.
final class TextAgentLegacyCompiler: TargetRecipeCompiler {
    let supportedDestinations: [TargetDestination] = [.claudeTextAgent, .perplexityResearch, .agenticIDEWorkflow]
    private let resolver = VariableResolver()

    func compile(
        ir: CanonicalPromptIR,
        recipe: RecipeProfile,
        mixMode: MixMode,
        variables: [String: String],
        legacyOptions: EnhancementOptions
    ) -> TargetCompiledDraft {
        let legacyTarget = recipe.destination.legacyPromptTarget
        var provenance: [ProvenanceEntry] = [
            ProvenanceEntry(source: .userAuthored, section: "Draft", note: "Original user text preserved")
        ]

        let compiledBody: String
        if mixMode == .neat {
            let trimmed = TargetCompilationSupport.applyExplicitVariables(ir.rawInput.trimmingCharacters(in: .whitespacesAndNewlines), values: variables, resolver: resolver)
            let builder = PromptBuilderRegistry().builder(for: legacyTarget)
            let ctx = PromptBuildContext(
                goal: trimmed,
                context: ir.ingredients.sceneContext,
                constraints: ir.ingredients.constraints,
                deliverables: ir.ingredients.deliverables,
                variables: variables
            )
            let sections = PromptSectionsConfig(
                includeGoal: true,
                includeContext: !ir.ingredients.sceneContext.isEmpty,
                includeConstraints: !ir.ingredients.constraints.isEmpty,
                includeDeliverables: !ir.ingredients.deliverables.isEmpty
            )
            compiledBody = builder?.build(ctx: ctx, sections: sections) ?? trimmed
            provenance.append(ProvenanceEntry(source: .providerProfile, section: "Playbook Wrapper", note: "Wrapped minimally using \(legacyTarget.rawValue) playbook"))
        } else {
            let modelFamily: ModelFamily = {
                switch recipe.destination {
                case .claudeTextAgent: return .anthropicClaudeStyle
                case .perplexityResearch: return .openAIGPTStyle
                case .agenticIDEWorkflow: return .anthropicClaudeStyle
                default: return .openAIGPTStyle
                }
            }()
            let scenario: ScenarioProfile = {
                switch recipe.destination {
                case .perplexityResearch: return .researchSummarization
                case .agenticIDEWorkflow: return .ideCodingAssistant
                default: return ir.intentKind == .codingAgent ? .ideCodingAssistant : .generalAssistant
                }
            }()
            let context = HeuristicOptimizationContext(target: legacyTarget, scenario: scenario)
            let optimized = HeuristicPromptOptimizer.optimize(ir.rawInput, context: context)
            let built = mixMode == .shaken
                ? OfflinePromptOptimizer().optimize(
                    OptimizationInput(
                        rawUserPrompt: optimized.optimizedText,
                        modelFamily: modelFamily,
                        scenario: scenario,
                        userOverrides: nil
                    )
                ).optimizedPrompt
                : optimized.optimizedText
            let resolved = TargetCompilationSupport.applyExplicitVariables(built, values: variables, resolver: resolver)
            compiledBody = TargetCompilationSupport.appendMissingProtectedTokens(to: resolved, ir: ir, negativePrompt: nil)
            provenance.append(ProvenanceEntry(source: .heuristicTransform, section: "Playbook + Heuristics", note: "Compiled with \(legacyTarget.rawValue) domain rules"))
        }

        let payload: [String: Any] = [
            "target": recipe.destination.rawValue,
            "model": recipe.modelID,
            "prompt": compiledBody
        ]

        return TargetCompiledDraft(
            compiledPrompt: compiledBody,
            negativePrompt: nil,
            systemInstructions: nil,
            structuredPayloadJSON: TargetCompilationSupport.prettyJSONString(payload),
            recommendedParameters: [
                "target": recipe.destination.rawValue,
                "model": recipe.modelID,
                "mode": mixMode.displayName
            ],
            resolvedParameters: ir.ingredients.technicalParams,
            provenance: provenance
        )
    }
}
