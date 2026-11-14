import Foundation

final class GrokImagineCompiler: TargetRecipeCompiler {
    let supportedDestinations: [TargetDestination] = [.grokImagineImage, .grokImagineVideo]
    private let resolver = VariableResolver()

    func compile(
        ir: CanonicalPromptIR,
        recipe: RecipeProfile,
        mixMode: MixMode,
        variables: [String: String],
        legacyOptions: EnhancementOptions
    ) -> TargetCompiledDraft {
        switch recipe.destination {
        case .grokImagineImage:
            return compileImage(ir: ir, recipe: recipe, mixMode: mixMode, variables: variables)
        case .grokImagineVideo:
            return compileVideo(ir: ir, recipe: recipe, mixMode: mixMode, variables: variables)
        default:
            return compileImage(ir: ir, recipe: recipe, mixMode: mixMode, variables: variables)
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
        let resolution = (ir.ingredients.technicalParams.resolutionTier ?? "1k").lowercased()
        let count = max(1, min(10, ir.ingredients.technicalParams.batchCount ?? 1))

        var resolvedParams = ir.ingredients.technicalParams
        resolvedParams.aspectRatio = aspectRatio
        resolvedParams.resolutionTier = resolution
        resolvedParams.batchCount = count

        let hasRefs = !ir.ingredients.referenceAssets.isEmpty
        var payload: [String: Any] = [
            "model": recipe.modelID,
            "prompt": prompt,
            "aspect_ratio": aspectRatio,
            "resolution": resolution,
            "n": count,
            "response_format": "url"
        ]
        if hasRefs {
            payload["images"] = ir.ingredients.referenceAssets.map { [
                "label": $0.label,
                "role": $0.role.rawValue,
                "uri": $0.pathOrURI
            ] }
        }

        let endpoint = hasRefs ? "/v1/images/edits" : "/v1/images/generations"
        return TargetCompiledDraft(
            compiledPrompt: prompt,
            negativePrompt: nil,
            systemInstructions: nil,
            structuredPayloadJSON: TargetCompilationSupport.prettyJSONString(payload),
            recommendedParameters: [
                "model": recipe.modelID,
                "endpoint": endpoint,
                "aspect_ratio": aspectRatio,
                "resolution": resolution,
                "n": "\(count)"
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

        let aspectRatio = ir.ingredients.technicalParams.aspectRatio ?? "16:9"
        let resolution = (ir.ingredients.technicalParams.resolutionTier ?? "720p").lowercased()
        let duration = Int((ir.ingredients.technicalParams.durationSeconds ?? 8).rounded())

        var resolvedParams = ir.ingredients.technicalParams
        resolvedParams.aspectRatio = aspectRatio
        resolvedParams.resolutionTier = resolution
        resolvedParams.durationSeconds = Double(duration)

        var payload: [String: Any] = [
            "model": recipe.modelID,
            "prompt": prompt,
            "duration": duration,
            "aspect_ratio": aspectRatio,
            "resolution": resolution
        ]

        let imageRefs = ir.ingredients.referenceAssets.filter { $0.role != .voice && $0.role != .startFrame && $0.role != .endFrame }
        if !imageRefs.isEmpty {
            payload["reference_images"] = imageRefs.map { ["label": $0.label, "role": $0.role.rawValue, "uri": $0.pathOrURI] }
        }
        let voiceRefs = ir.ingredients.referenceAssets.filter { $0.role == .voice }
        if !voiceRefs.isEmpty {
            payload["voice_references"] = voiceRefs.map { ["label": $0.label, "uri": $0.pathOrURI] }
        }
        if let startFrame = ir.ingredients.referenceAssets.first(where: { $0.role == .startFrame }) {
            payload["start_frame"] = startFrame.pathOrURI
        }
        if let endFrame = ir.ingredients.referenceAssets.first(where: { $0.role == .endFrame }) {
            payload["end_frame"] = endFrame.pathOrURI
        }

        return TargetCompiledDraft(
            compiledPrompt: prompt,
            negativePrompt: nil,
            systemInstructions: nil,
            structuredPayloadJSON: TargetCompilationSupport.prettyJSONString(payload),
            recommendedParameters: [
                "model": recipe.modelID,
                "endpoint": "/v1/videos/generations",
                "duration": "\(duration)s",
                "aspect_ratio": aspectRatio,
                "resolution": resolution
            ],
            resolvedParameters: resolvedParams,
            provenance: provenance
        )
    }
}
