import Foundation

final class DexDiffusionCompiler: TargetRecipeCompiler {
    let supportedDestinations: [TargetDestination] = [.dexDiffusionImage]
    private let resolver = VariableResolver()

    func compile(
        ir: CanonicalPromptIR,
        recipe: RecipeProfile,
        mixMode: MixMode,
        variables: [String: String],
        legacyOptions: EnhancementOptions
    ) -> TargetCompiledDraft {
        let isFlux = recipe.modelID.lowercased().contains("flux")
        let isPony = recipe.modelID.lowercased().contains("pony")

        var (prompt, provenance) = TargetCompilationSupport.buildVisualProse(
            ir: ir,
            recipe: recipe,
            mixMode: mixMode,
            variables: variables,
            resolver: resolver,
            includePositiveExclusions: false
        )

        // Pony preserves quality score/rating/source tags cleanly ahead of visual prose.
        if isPony && !ir.lexResult.spans(of: .qualityScoreTag).isEmpty {
            let existingTags = ir.lexResult.spans(of: .qualityScoreTag).map(\.text)
            let dedupPrefix = existingTags.joined(separator: ", ")
            if !prompt.lowercased().hasPrefix(dedupPrefix.lowercased()) {
                prompt = "\(dedupPrefix), \(prompt)"
            }
        }

        // Compute model-aware negative prompt
        var negativeParts: [String] = []
        if !ir.ingredients.negativeIntent.isEmpty {
            negativeParts.append(contentsOf: ir.ingredients.negativeIntent)
        }
        if ir.ingredients.separateOutputsRequested && !negativeParts.contains(where: { $0.lowercased().contains("collage") }) {
            negativeParts.append("collage, split grid, contact sheet, diptych, triptych")
        }
        if !isFlux && mixMode != .neat && !recipe.defaultNegativePrompt.isEmpty {
            negativeParts.append(recipe.defaultNegativePrompt)
        }

        let negativePrompt = negativeParts.isEmpty
            ? nil
            : negativeParts.joined(separator: ", ")

        let dims = TargetCompilationSupport.resolveDimensions(
            params: ir.ingredients.technicalParams,
            defaultSize: isFlux || recipe.modelID.contains("sdxl") ? 1024 : 512
        )
        let defaultSteps: Int = {
            if let s = ir.ingredients.technicalParams.steps { return s }
            if recipe.modelID.contains("klein") { return 4 }
            if recipe.modelID.contains("turbo") { return 4 }
            if isFlux { return 20 }
            return 28
        }()
        let defaultCFG: Double = {
            if let cfg = ir.ingredients.technicalParams.cfgScale { return cfg }
            if recipe.modelID.contains("klein") { return 1.0 }
            if recipe.modelID.contains("turbo") { return 2.0 }
            if isFlux { return 3.5 }
            return 7.0
        }()

        var resolvedParams = ir.ingredients.technicalParams
        resolvedParams.width = dims.width
        resolvedParams.height = dims.height
        resolvedParams.steps = defaultSteps
        resolvedParams.cfgScale = defaultCFG

        var controlledPayload: [String: Any] = [
            "target": recipe.modelID,
            "prompt": prompt,
            "width": dims.width,
            "height": dims.height,
            "steps": defaultSteps,
            "cfg": defaultCFG
        ]
        if let neg = negativePrompt, !neg.isEmpty {
            controlledPayload["negative_prompt"] = neg
        }
        if let seed = resolvedParams.seed {
            controlledPayload["seed"] = seed
        }
        if let count = resolvedParams.batchCount, count > 1 {
            controlledPayload["batch_count"] = count
            controlledPayload["output_mode"] = ir.ingredients.separateOutputsRequested ? "separate_images" : "batch"
        }
        if !ir.lexResult.wildcards.isEmpty {
            controlledPayload["wildcards"] = ir.lexResult.wildcards
        }
        if !ir.lexResult.loras.isEmpty {
            controlledPayload["loras"] = ir.lexResult.loras
        }

        let summaryParams: [String: String] = [
            "target": recipe.modelID,
            "endpoint": "/api/actions/generate-controlled",
            "dimensions": "\(dims.width)x\(dims.height)",
            "steps": "\(defaultSteps)",
            "cfg": String(format: "%.1f", defaultCFG),
            "maxLength": "4000"
        ]

        return TargetCompiledDraft(
            compiledPrompt: prompt,
            negativePrompt: negativePrompt,
            systemInstructions: nil,
            structuredPayloadJSON: TargetCompilationSupport.prettyJSONString(controlledPayload),
            recommendedParameters: summaryParams,
            resolvedParameters: resolvedParams,
            provenance: provenance
        )
    }
}
