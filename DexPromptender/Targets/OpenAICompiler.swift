import Foundation

final class OpenAICompiler: TargetRecipeCompiler {
    let supportedDestinations: [TargetDestination] = [.openAIImage, .openAITextAgent]
    private let resolver = VariableResolver()

    func compile(
        ir: CanonicalPromptIR,
        recipe: RecipeProfile,
        mixMode: MixMode,
        variables: [String: String],
        legacyOptions: EnhancementOptions
    ) -> TargetCompiledDraft {
        switch recipe.destination {
        case .openAIImage:
            return compileImage(ir: ir, recipe: recipe, mixMode: mixMode, variables: variables)
        case .openAITextAgent:
            return compileTextResponses(ir: ir, recipe: recipe, mixMode: mixMode, variables: variables, legacyOptions: legacyOptions)
        default:
            return compileTextResponses(ir: ir, recipe: recipe, mixMode: mixMode, variables: variables, legacyOptions: legacyOptions)
        }
    }

    private func compileImage(
        ir: CanonicalPromptIR,
        recipe: RecipeProfile,
        mixMode: MixMode,
        variables: [String: String]
    ) -> TargetCompiledDraft {
        var (prompt, provenance) = TargetCompilationSupport.buildVisualProse(
            ir: ir,
            recipe: recipe,
            mixMode: mixMode,
            variables: variables,
            resolver: resolver,
            includePositiveExclusions: true
        )

        if !ir.lexResult.quotedLiterals.isEmpty && !prompt.contains("Render exact text") {
            let literals = ir.lexResult.quotedLiterals.map { "\"\($0)\"" }.joined(separator: ", ")
            prompt += "\nRender exact literal typography cleanly without typos: \(literals)."
            provenance.append(ProvenanceEntry(source: .providerProfile, section: "Typography", note: "Added GPT Image literal text rendering reinforcement"))
        }

        let size: String = {
            switch ir.ingredients.technicalParams.aspectRatio {
            case "3:2", "16:9": return "1536x1024"
            case "2:3", "9:16": return "1024x1536"
            case "1:1": return "1024x1024"
            default: return "auto"
            }
        }()

        let quality = (ir.ingredients.technicalParams.qualityTier ?? "high").lowercased()
        let background = (ir.ingredients.technicalParams.backgroundMode ?? "auto").lowercased()
        let outputFormat = (ir.ingredients.technicalParams.outputFormat ?? (background == "transparent" ? "png" : "png")).lowercased()
        let fidelity = (ir.ingredients.technicalParams.inputFidelity ?? "high").lowercased()
        let count = max(1, min(10, ir.ingredients.technicalParams.batchCount ?? 1))

        var resolvedParams = ir.ingredients.technicalParams
        resolvedParams.resolutionTier = size
        resolvedParams.qualityTier = quality
        resolvedParams.backgroundMode = background
        resolvedParams.outputFormat = outputFormat
        resolvedParams.inputFidelity = fidelity
        resolvedParams.batchCount = count

        let hasRefsOrMask = !ir.ingredients.referenceAssets.isEmpty
        let endpoint = hasRefsOrMask ? "/v1/images/edits" : "/v1/images/generations"

        var payload: [String: Any] = [
            "model": recipe.modelID,
            "prompt": prompt,
            "size": size,
            "quality": quality,
            "background": background,
            "output_format": outputFormat,
            "n": count
        ]
        if hasRefsOrMask {
            payload["input_fidelity"] = fidelity
            let imageAssets = ir.ingredients.referenceAssets.filter { $0.role != .mask }
            if !imageAssets.isEmpty {
                payload["image"] = imageAssets.map { ["label": $0.label, "role": $0.role.rawValue, "uri": $0.pathOrURI] }
            }
            if let mask = ir.ingredients.referenceAssets.first(where: { $0.role == .mask }) {
                payload["mask"] = mask.pathOrURI
            }
        }

        return TargetCompiledDraft(
            compiledPrompt: prompt,
            negativePrompt: nil,
            systemInstructions: nil,
            structuredPayloadJSON: TargetCompilationSupport.prettyJSONString(payload),
            recommendedParameters: [
                "model": recipe.modelID,
                "endpoint": endpoint,
                "size": size,
                "quality": quality,
                "background": background,
                "output_format": outputFormat
            ],
            resolvedParameters: resolvedParams,
            provenance: provenance
        )
    }

    private func compileTextResponses(
        ir: CanonicalPromptIR,
        recipe: RecipeProfile,
        mixMode: MixMode,
        variables: [String: String],
        legacyOptions: EnhancementOptions
    ) -> TargetCompiledDraft {
        var provenance: [ProvenanceEntry] = [
            ProvenanceEntry(source: .userAuthored, section: "Draft", note: "Original task intent preserved")
        ]

        let scenario: ScenarioProfile = {
            switch ir.intentKind {
            case .codingAgent: return .ideCodingAssistant
            case .researchAnalysis: return .researchSummarization
            case .structuredOutput: return .jsonStructuredOutput
            default: return .generalAssistant
            }
        }()

        let instructions = "You are a precise assistant operating on explicit user requirements. Preserve all literal constraints, file paths, code blocks, and output schemas. Label uncertainty explicitly rather than guessing."
        let compiledBody: String

        if mixMode == .neat {
            compiledBody = TargetCompilationSupport.applyExplicitVariables(ir.rawInput.trimmingCharacters(in: .whitespacesAndNewlines), values: variables, resolver: resolver)
            provenance.append(ProvenanceEntry(source: .deterministicParser, section: "Neat Hygiene", note: "Preserved verbatim structure with minimal normalization"))
        } else {
            let enhanced = TargetCompilationSupport.enhanceTextTask(
                rawInput: ir.rawInput,
                ir: ir,
                recipe: recipe,
                mixMode: mixMode,
                legacyTarget: .geminiChatGPT,
                modelFamily: .openAIGPTStyle,
                scenario: scenario,
                variables: variables,
                resolver: resolver
            )
            compiledBody = enhanced.prompt
            provenance.append(ProvenanceEntry(source: .heuristicTransform, section: "OpenAI Prompt Engineering", note: enhanced.sectionNote))
        }

        let effort = ir.ingredients.technicalParams.reasoningEffort ?? (ir.intentKind == .codingAgent || ir.intentKind == .researchAnalysis ? "high" : "medium")
        var resolvedParams = ir.ingredients.technicalParams
        resolvedParams.reasoningEffort = effort

        var payload: [String: Any] = [
            "model": recipe.modelID,
            "instructions": instructions,
            "input": compiledBody,
            "reasoning": ["effort": effort]
        ]

        if ir.intentKind == .structuredOutput {
            payload["text"] = [
                "format": [
                    "type": "json_schema",
                    "name": "promptender_structured_response",
                    "strict": true
                ]
            ]
        }

        return TargetCompiledDraft(
            compiledPrompt: compiledBody,
            negativePrompt: nil,
            systemInstructions: instructions,
            structuredPayloadJSON: TargetCompilationSupport.prettyJSONString(payload),
            recommendedParameters: [
                "model": recipe.modelID,
                "endpoint": "/v1/responses",
                "reasoning.effort": effort,
                "format": ir.intentKind == .structuredOutput ? "json_schema" : "markdown"
            ],
            resolvedParameters: resolvedParams,
            provenance: provenance
        )
    }
}
