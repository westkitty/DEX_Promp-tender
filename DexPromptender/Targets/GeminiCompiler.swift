import Foundation

final class GeminiCompiler: TargetRecipeCompiler {
    let supportedDestinations: [TargetDestination] = [.geminiImage, .geminiVideo, .geminiTextAgent]
    private let resolver = VariableResolver()

    func compile(
        ir: CanonicalPromptIR,
        recipe: RecipeProfile,
        mixMode: MixMode,
        variables: [String: String],
        legacyOptions: EnhancementOptions
    ) -> TargetCompiledDraft {
        switch recipe.destination {
        case .geminiImage:
            return compileImage(ir: ir, recipe: recipe, mixMode: mixMode, variables: variables)
        case .geminiVideo:
            return compileVideo(ir: ir, recipe: recipe, mixMode: mixMode, variables: variables)
        case .geminiTextAgent:
            return compileTextAgent(ir: ir, recipe: recipe, mixMode: mixMode, variables: variables, legacyOptions: legacyOptions)
        default:
            return compileTextAgent(ir: ir, recipe: recipe, mixMode: mixMode, variables: variables, legacyOptions: legacyOptions)
        }
    }

    private func compileImage(
        ir: CanonicalPromptIR,
        recipe: RecipeProfile,
        mixMode: MixMode,
        variables: [String: String]
    ) -> TargetCompiledDraft {
        let (prompt, provenance) = TargetCompilationSupport.buildVisualProse(
            ir: ir,
            recipe: recipe,
            mixMode: mixMode,
            variables: variables,
            resolver: resolver,
            includePositiveExclusions: true
        )

        let aspectRatio = ir.ingredients.technicalParams.aspectRatio ?? "1:1"
        let imageSize = (ir.ingredients.technicalParams.resolutionTier ?? "2K").uppercased()
        let thinkingLevel = ir.ingredients.technicalParams.thinkingLevel ?? "medium"

        var resolvedParams = ir.ingredients.technicalParams
        resolvedParams.aspectRatio = aspectRatio
        resolvedParams.resolutionTier = imageSize
        resolvedParams.thinkingLevel = thinkingLevel

        var parts: [[String: Any]] = [["text": prompt]]
        for asset in ir.ingredients.referenceAssets {
            parts.append([
                "reference_hint": [
                    "label": asset.label,
                    "role": asset.role.rawValue,
                    "uri": asset.pathOrURI
                ]
            ])
        }

        let payload: [String: Any] = [
            "model": recipe.modelID,
            "contents": [
                ["role": "user", "parts": parts]
            ],
            "generationConfig": [
                "responseModalities": ["IMAGE", "TEXT"],
                "imageConfig": [
                    "aspectRatio": aspectRatio,
                    "imageSize": imageSize
                ],
                "thinkingConfig": [
                    "thinkingLevel": thinkingLevel
                ]
            ]
        ]

        return TargetCompiledDraft(
            compiledPrompt: prompt,
            negativePrompt: nil,
            systemInstructions: nil,
            structuredPayloadJSON: TargetCompilationSupport.prettyJSONString(payload),
            recommendedParameters: [
                "model": recipe.modelID,
                "endpoint": "/v1beta/models/\(recipe.modelID):generateContent",
                "aspectRatio": aspectRatio,
                "imageSize": imageSize,
                "thinkingLevel": thinkingLevel
            ],
            resolvedParameters: resolvedParams,
            provenance: provenance
        )
    }

    private func compileVideo(
        ir: CanonicalPromptIR,
        recipe: RecipeProfile,
        mixMode: MixMode,
        variables: [String: String]
    ) -> TargetCompiledDraft {
        let (prompt, provenance) = TargetCompilationSupport.buildVideoScript(
            ir: ir,
            recipe: recipe,
            mixMode: mixMode,
            variables: variables,
            resolver: resolver
        )

        let isVeo = recipe.modelID.lowercased().contains("veo")
        let aspectRatio = ir.ingredients.technicalParams.aspectRatio ?? "16:9"
        let resolution = (ir.ingredients.technicalParams.resolutionTier ?? "1080p")
        let defaultDur: Double = isVeo ? 6 : 8
        let duration = Int((ir.ingredients.technicalParams.durationSeconds ?? defaultDur).rounded())

        var resolvedParams = ir.ingredients.technicalParams
        resolvedParams.aspectRatio = aspectRatio
        resolvedParams.resolutionTier = resolution
        resolvedParams.durationSeconds = Double(duration)

        var payload: [String: Any] = [
            "model": recipe.modelID,
            "prompt": prompt,
            "config": [
                "aspectRatio": aspectRatio,
                "resolution": resolution,
                "durationSeconds": duration,
                "generateAudio": !ir.ingredients.audioDialogue.suppressAudio
            ]
        ]
        if !ir.lexResult.videoRefs.isEmpty {
            payload["videoEditReferences"] = ir.lexResult.videoRefs
        }
        if !ir.ingredients.referenceAssets.isEmpty {
            payload["referenceMedia"] = ir.ingredients.referenceAssets.map { [
                "label": $0.label,
                "role": $0.role.rawValue,
                "uri": $0.pathOrURI
            ] }
        }

        return TargetCompiledDraft(
            compiledPrompt: prompt,
            negativePrompt: nil,
            systemInstructions: nil,
            structuredPayloadJSON: TargetCompilationSupport.prettyJSONString(payload),
            recommendedParameters: [
                "model": recipe.modelID,
                "endpoint": isVeo ? "predictLongRunning(\(recipe.modelID))" : "generateContent(\(recipe.modelID))",
                "aspectRatio": aspectRatio,
                "resolution": resolution,
                "duration": "\(duration)s"
            ],
            resolvedParameters: resolvedParams,
            provenance: provenance
        )
    }

    private func compileTextAgent(
        ir: CanonicalPromptIR,
        recipe: RecipeProfile,
        mixMode: MixMode,
        variables: [String: String],
        legacyOptions: EnhancementOptions
    ) -> TargetCompiledDraft {
        var provenance: [ProvenanceEntry] = [
            ProvenanceEntry(source: .userAuthored, section: "Draft", note: "Original Gemini task preserved")
        ]

        let scenario: ScenarioProfile = {
            switch ir.intentKind {
            case .codingAgent: return .ideCodingAssistant
            case .researchAnalysis: return .researchSummarization
            case .structuredOutput: return .jsonStructuredOutput
            default: return .generalAssistant
            }
        }()

        let systemInstruction = "Follow every explicit constraint cleanly, ground claims in provided context, and keep protected identifiers verbatim."
        let compiledBody: String

        if mixMode == .neat {
            compiledBody = TargetCompilationSupport.applyExplicitVariables(ir.rawInput.trimmingCharacters(in: .whitespacesAndNewlines), values: variables, resolver: resolver)
            provenance.append(ProvenanceEntry(source: .deterministicParser, section: "Neat Hygiene", note: "Preserved original layout cleanly"))
        } else {
            let enhanced = TargetCompilationSupport.enhanceTextTask(
                rawInput: ir.rawInput,
                ir: ir,
                recipe: recipe,
                mixMode: mixMode,
                legacyTarget: .geminiChatGPT,
                modelFamily: .googleGeminiStyle,
                scenario: scenario,
                variables: variables,
                resolver: resolver
            )
            compiledBody = enhanced.prompt
            provenance.append(ProvenanceEntry(source: .heuristicTransform, section: "Gemini Prompt Engineering", note: enhanced.sectionNote))
        }

        var generationConfig: [String: Any] = [
            "temperature": ir.intentKind == .codingAgent || ir.intentKind == .structuredOutput ? 0.2 : 0.4
        ]
        if ir.intentKind == .structuredOutput {
            generationConfig["responseMimeType"] = "application/json"
            generationConfig["responseJsonSchema"] = [
                "type": "object",
                "properties": [
                    "summary": ["type": "string"],
                    "result": ["type": "object"]
                ],
                "required": ["summary", "result"]
            ]
        }

        let payload: [String: Any] = [
            "model": recipe.modelID,
            "systemInstruction": ["parts": [["text": systemInstruction]]],
            "contents": [["role": "user", "parts": [["text": compiledBody]]]],
            "generationConfig": generationConfig
        ]

        return TargetCompiledDraft(
            compiledPrompt: compiledBody,
            negativePrompt: nil,
            systemInstructions: systemInstruction,
            structuredPayloadJSON: TargetCompilationSupport.prettyJSONString(payload),
            recommendedParameters: [
                "model": recipe.modelID,
                "endpoint": "/v1beta/models/\(recipe.modelID):generateContent",
                "responseMimeType": ir.intentKind == .structuredOutput ? "application/json" : "text/plain"
            ],
            resolvedParameters: ir.ingredients.technicalParams,
            provenance: provenance
        )
    }
}
