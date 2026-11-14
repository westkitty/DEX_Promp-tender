import Foundation

struct TargetCompiledDraft {
    let compiledPrompt: String
    let negativePrompt: String?
    let systemInstructions: String?
    let structuredPayloadJSON: String
    let recommendedParameters: [String: String]
    let resolvedParameters: TechnicalParameterSet
    let provenance: [ProvenanceEntry]
}

protocol TargetRecipeCompiler {
    var supportedDestinations: [TargetDestination] { get }
    func compile(
        ir: CanonicalPromptIR,
        recipe: RecipeProfile,
        mixMode: MixMode,
        variables: [String: String],
        legacyOptions: EnhancementOptions
    ) -> TargetCompiledDraft
}

enum TargetCompilationSupport {
    /// Resolves template variables `{var}` only when values were explicitly provided;
    /// leaves unfilled placeholders untouched so intent is never guessed.
    static func applyExplicitVariables(_ text: String, values: [String: String], resolver: VariableResolver) -> String {
        guard !values.isEmpty else { return text }
        return resolver.resolve(text: text, values: values).resolvedText
    }

    /// Formats non-empty clauses into clean single prose or bulleted paragraphs.
    static func joinNonEmpty(_ parts: [String], separator: String = "\n\n") -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }

    /// Strips inline `--no ...` and `NOT: ...` directives cleanly when relocating exclusions to target fields.
    static func stripInlineNoFlags(_ text: String) -> String {
        var working = text
        if let regex = try? NSRegularExpression(pattern: #"(?i)\s+--no\s+[^\n]+"#) {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            working = regex.stringByReplacingMatches(in: working, range: range, withTemplate: "")
        }
        return working.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Computes width/height for image aspect ratios when caller specifies ratio without explicit pixel dimensions.
    static func resolveDimensions(params: TechnicalParameterSet, defaultSize: Int = 1024) -> (width: Int, height: Int) {
        if let w = params.width, let h = params.height, w > 0, h > 0 {
            return (w, h)
        }
        switch params.aspectRatio {
        case "16:9": return (1344, 768)
        case "9:16": return (768, 1344)
        case "4:3": return (1152, 896)
        case "3:4": return (896, 1152)
        case "3:2": return (1216, 832)
        case "2:3": return (832, 1216)
        case "21:9": return (1536, 640)
        default: return (defaultSize, defaultSize)
        }
    }

    /// Ensures any protected span that belongs in the prompt stays preserved verbatim if heuristic cleanup trimmed it.
    static func appendMissingProtectedTokens(
        to prompt: String,
        ir: CanonicalPromptIR,
        negativePrompt: String?,
        includeRelocatable: Bool = false
    ) -> String {
        var result = prompt
        let combinedLower = (prompt + "\n" + (negativePrompt ?? "")).lowercased()
        var missingTokens: [String] = []

        for invariant in ir.invariants where invariant.isEnabled {
            switch invariant.kind {
            case .preserveProtectedSpan, .preserveTextLiteral, .preserveReferenceBinding:
                let token = invariant.requiredToken
                if !includeRelocatable && ir.lexResult.spans.contains(where: { $0.text == token && $0.kind.canRelocateToTargetSlot }) {
                    continue
                }
                if !combinedLower.contains(token.lowercased()) {
                    missingTokens.append(token)
                }
            case .preserveSubjectCount:
                let countToken = invariant.requiredToken
                if !combinedLower.contains(countToken.lowercased()) {
                    missingTokens.append(countToken)
                }
            case .forbidCollageMerge:
                if !combinedLower.contains("separate") && !combinedLower.contains("individual") {
                    missingTokens.append("Render as separate distinct images, NOT a collage.")
                }
            case .preserveExclusion:
                break
            }
        }

        if !missingTokens.isEmpty {
            let suffix = missingTokens.joined(separator: " ")
            result = result.isEmpty ? suffix : "\(result)\n\(suffix)"
        }
        return result
    }

    static func prettyJSONString(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    static func buildVisualProse(
        ir: CanonicalPromptIR,
        recipe: RecipeProfile,
        mixMode: MixMode,
        variables: [String: String],
        resolver: VariableResolver,
        includePositiveExclusions: Bool
    ) -> (prompt: String, provenance: [ProvenanceEntry]) {
        var provenance: [ProvenanceEntry] = [
            ProvenanceEntry(source: .userAuthored, section: "Draft", note: "Original user intent preserved"),
            ProvenanceEntry(source: .deterministicParser, section: "Ingredients", note: "Extracted visual, spatial, and technical cues")
        ]

        let cleanedBody = stripInlineNoFlags(ir.rawInput)
        var coreLines: [String] = []

        if mixMode == .neat {
            // Neat preserves user line structure without prefix/tag noise
            let neatText = cleanedBody
                .components(separatedBy: .newlines)
                .filter { line in
                    let low = line.trimmingCharacters(in: .whitespaces).lowercased()
                    return !low.hasPrefix("not:") && !low.hasPrefix("do not:") && !low.hasPrefix("negative:")
                }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !recipe.systemPrelude.isEmpty && !neatText.lowercased().contains(recipe.systemPrelude.lowercased()) {
                coreLines.append(recipe.systemPrelude)
                provenance.append(ProvenanceEntry(source: .providerProfile, section: "Prelude", note: "Added \(recipe.modelID) quality tag prelude"))
            }
            coreLines.append(neatText)
        } else {
            // Stirred / Shaken builds an ordered target-native visual brief
            var blocks: [String] = []
            if !recipe.systemPrelude.isEmpty && !cleanedBody.lowercased().contains(recipe.systemPrelude.lowercased()) {
                blocks.append(recipe.systemPrelude)
                provenance.append(ProvenanceEntry(source: .providerProfile, section: "Prelude", note: "Prepended \(recipe.modelID) prelude"))
            }

            let mainNarrative = [ir.ingredients.subject, ir.ingredients.sceneContext]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !mainNarrative.isEmpty {
                blocks.append(mainNarrative)
            }

            if !ir.ingredients.spatialRelations.isEmpty {
                blocks.append("Spatial layout: \(ir.ingredients.spatialRelations.joined(separator: ", ")).")
            }

            if ir.ingredients.separateOutputsRequested {
                blocks.append("Render strictly as separate individual images (one subject/scene per standalone frame, never combined into a collage or grid).")
                provenance.append(ProvenanceEntry(source: .providerProfile, section: "Output Isolation", note: "Enforced separate-image non-collage instruction"))
            }

            var visualQualities: [String] = []
            if !ir.ingredients.styleMedium.isEmpty {
                visualQualities.append("Style: \(ir.ingredients.styleMedium)")
            } else if mixMode == .stirred || mixMode == .shaken {
                visualQualities.append(defaultStyleDirection(for: recipe, shaken: mixMode == .shaken))
            }

            if !ir.ingredients.cameraComposition.isEmpty {
                visualQualities.append("Camera: \(ir.ingredients.cameraComposition)")
            } else if mixMode == .stirred || mixMode == .shaken {
                visualQualities.append(defaultCameraDirection(for: recipe, shaken: mixMode == .shaken))
            }

            if !ir.ingredients.lightingAtmosphere.isEmpty {
                visualQualities.append("Lighting: \(ir.ingredients.lightingAtmosphere)")
            } else if mixMode == .stirred || mixMode == .shaken {
                visualQualities.append(defaultLightingDirection(for: recipe, shaken: mixMode == .shaken))
            }

            if mixMode == .shaken {
                visualQualities.append("Materiality & Depth: crisp surface micro-textures, natural optical depth-of-field, and cohesive palette separation across foreground and background")
                provenance.append(ProvenanceEntry(source: .heuristicTransform, section: "Creative Visual Expansion", note: "Applied Shaken target art direction, lighting choreography, and optical depth without overriding locks"))
            } else if mixMode == .stirred {
                provenance.append(ProvenanceEntry(source: .heuristicTransform, section: "Balanced Visual Enhancement", note: "Synthesized missing composition, lighting, and material cues tailored to \(recipe.modelID)"))
            }

            if !visualQualities.isEmpty {
                blocks.append(visualQualities.joined(separator: ". ") + ".")
            }

            if !ir.ingredients.constraints.isEmpty {
                blocks.append("Constraints: \(ir.ingredients.constraints.joined(separator: "; ")).")
            }

            if includePositiveExclusions && !ir.ingredients.negativeIntent.isEmpty {
                blocks.append("Strictly exclude: \(ir.ingredients.negativeIntent.joined(separator: ", ")).")
                provenance.append(ProvenanceEntry(source: .providerProfile, section: "Exclusions", note: "Encoded exclusions positively for negative_prompt-less API"))
            }

            coreLines.append(joinNonEmpty(blocks, separator: "\n"))
        }

        var compiled = applyExplicitVariables(joinNonEmpty(coreLines, separator: "\n"), values: variables, resolver: resolver)
        compiled = appendMissingProtectedTokens(to: compiled, ir: ir, negativePrompt: includePositiveExclusions ? nil : ir.ingredients.negativeIntent.joined(separator: ", "))

        if !recipe.styleSuffix.isEmpty && !compiled.contains(recipe.styleSuffix) {
            compiled += "\n\(recipe.styleSuffix)"
        }

        return (compiled.trimmingCharacters(in: .whitespacesAndNewlines), provenance)
    }

    static func buildVideoScript(
        ir: CanonicalPromptIR,
        recipe: RecipeProfile,
        mixMode: MixMode,
        variables: [String: String],
        resolver: VariableResolver
    ) -> (prompt: String, provenance: [ProvenanceEntry]) {
        var provenance: [ProvenanceEntry] = [
            ProvenanceEntry(source: .userAuthored, section: "Draft", note: "Original temporal video intent preserved"),
            ProvenanceEntry(source: .deterministicParser, section: "Video Timeline", note: "Structured beats, continuity, camera motion, and audio cues")
        ]

        var sections: [String] = []

        if !ir.lexResult.videoRefs.isEmpty {
            sections.append("CONTINUITY REFERENCES: \(ir.lexResult.videoRefs.joined(separator: ", "))")
        }

        if !ir.ingredients.referenceAssets.isEmpty {
            let refLines = ir.ingredients.referenceAssets.map { "- [\($0.role.displayName)] \($0.label) (\($0.pathOrURI))" }
            sections.append("REFERENCE BINDINGS:\n" + refLines.joined(separator: "\n"))
        }

        if !ir.ingredients.subject.isEmpty && ir.ingredients.temporalTimeline.isEmpty {
            sections.append("SCENE PREMISE:\n\(ir.ingredients.subject)")
        }

        if !ir.ingredients.temporalTimeline.isEmpty {
            let timelineLines = ir.ingredients.temporalTimeline.map { beat -> String in
                var line = "[\(beat.timecodeLabel)] \(beat.visualAction)"
                if !beat.cameraMotion.isEmpty { line += " | Camera: \(beat.cameraMotion)" }
                if !beat.startState.isEmpty { line += " | Start: \(beat.startState)" }
                if !beat.endState.isEmpty { line += " | End: \(beat.endState)" }
                if !beat.audioCue.isEmpty { line += " | Audio: \(beat.audioCue)" }
                return line
            }
            sections.append("TEMPORAL SEQUENCE:\n" + timelineLines.joined(separator: "\n"))
        } else if mixMode != .neat {
            let cam = ir.ingredients.cameraComposition.isEmpty ? "Smooth stabilized motion tracking the subject" : ir.ingredients.cameraComposition
            sections.append("""
            TEMPORAL PROGRESSION:
            - Start State: Establish subject pose, scale, and environment cleanly from frame 1.
            - Motion & Action: \(ir.ingredients.action.isEmpty ? ir.rawInput : ir.ingredients.action)
            - Camera Trajectory: \(cam)
            - End State: Land on a clean, settled composition preserving identity and lighting continuity.
            """)
            provenance.append(ProvenanceEntry(source: .providerProfile, section: "Temporal Scaffold", note: "Structured start -> motion -> camera -> end continuity"))
        }

        if !ir.ingredients.continuityAnchors.isEmpty {
            sections.append("CONTINUITY ANCHORS:\n" + ir.ingredients.continuityAnchors.joined(separator: "\n"))
        }

        if !ir.ingredients.audioDialogue.isEmpty {
            var audioLines: [String] = []
            if ir.ingredients.audioDialogue.suppressAudio {
                audioLines.append("- Silent clip: do not synthesize speech or music.")
            } else {
                for line in ir.ingredients.audioDialogue.spokenDialogue {
                    audioLines.append("- Spoken Dialogue\(ir.ingredients.audioDialogue.requiresLipSync ? " (lip-sync)" : ""): \"\(line)\"")
                }
                for sfx in ir.ingredients.audioDialogue.soundEffects {
                    audioLines.append("- SFX: \(sfx)")
                }
                if !ir.ingredients.audioDialogue.ambientAudio.isEmpty {
                    audioLines.append("- Ambient Audio: \(ir.ingredients.audioDialogue.ambientAudio)")
                }
            }
            sections.append("AUDIO & DIALOGUE:\n" + audioLines.joined(separator: "\n"))
        }

        if !ir.ingredients.styleMedium.isEmpty || !ir.ingredients.lightingAtmosphere.isEmpty {
            let look = [ir.ingredients.styleMedium, ir.ingredients.lightingAtmosphere].filter { !$0.isEmpty }.joined(separator: ", ")
            sections.append("VISUAL LOOK & LIGHTING:\n\(look)")
        }

        if !ir.ingredients.negativeIntent.isEmpty {
            sections.append("EXCLUSIONS:\nAvoid \(ir.ingredients.negativeIntent.joined(separator: ", ")).")
        }

        var compiled = applyExplicitVariables(joinNonEmpty(sections, separator: "\n\n"), values: variables, resolver: resolver)
        compiled = appendMissingProtectedTokens(to: compiled, ir: ir, negativePrompt: nil)
        return (compiled, provenance)
    }

    static func defaultStyleDirection(for recipe: RecipeProfile, shaken: Bool) -> String {
        let model = recipe.modelID.lowercased()
        switch recipe.destination {
        case .dexDiffusionImage:
            if model.contains("pony") {
                return shaken
                    ? "Style & Render: rich illustrative lineweight, expressive shading, saturated color separation, clean crisp edges"
                    : "Style & Render: cohesive illustrative shading and clean silhouettes"
            }
            if model.contains("flux") {
                return shaken
                    ? "Art Direction: grounded editorial realism with authentic textures, subtle optical grain, and natural tonal transitions"
                    : "Art Direction: detailed natural prose emphasis on authentic textures and coherent surface materials"
            }
            return shaken
                ? "Visual Fidelity: high-detail photographic craft, rich surface micro-textures, crisp focus on primary subject"
                : "Visual Fidelity: crisp detail, fine surface textures, clean subject definition"
        case .openAIImage:
            return shaken
                ? "Design & Realism: high-clarity subject isolation, rich surface materiality, disciplined visual hierarchy, legible micro-detail"
                : "Design & Realism: clean visual hierarchy, crisp material rendering, balanced composition"
        case .geminiImage:
            return shaken
                ? "Editorial Finish: natural photographic realism, authentic fabric/skin/surface detail, organic tonal grading"
                : "Editorial Finish: grounded photographic detail and natural tonal balance"
        case .grokImagineImage:
            return shaken
                ? "Visual Style: vivid high-contrast storytelling frame, crisp focal clarity, rich environmental detail"
                : "Visual Style: crisp focal detail and expressive environmental atmosphere"
        default:
            return "Style: cohesive visual craft and clear subject emphasis"
        }
    }

    static func defaultCameraDirection(for recipe: RecipeProfile, shaken: Bool) -> String {
        if shaken {
            return "Composition & Lens: deliberate subject-first framing (35mm–50mm optical perspective), layered foreground/background depth, smooth bokeh falloff"
        }
        return "Composition: clean focal hierarchy with intentional framing and balanced negative space"
    }

    static func defaultLightingDirection(for recipe: RecipeProfile, shaken: Bool) -> String {
        if shaken {
            return "Lighting & Atmosphere: sculpted directional key light paired with subtle ambient fill, rim separation along silhouettes, and natural atmospheric depth"
        }
        return "Lighting: cohesive directional light with clean shadow definition and tonal depth"
    }

    /// Runs HeuristicPromptOptimizer + OfflinePromptOptimizer fallback so Stirred/Shaken text prompts
    /// always receive genuine structural enhancement rather than echoing short drafts verbatim.
    static func enhanceTextTask(
        rawInput: String,
        ir: CanonicalPromptIR,
        recipe: RecipeProfile,
        mixMode: MixMode,
        legacyTarget: PromptTarget,
        modelFamily: ModelFamily,
        scenario: ScenarioProfile,
        variables: [String: String],
        resolver: VariableResolver
    ) -> (prompt: String, sectionNote: String) {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = HeuristicOptimizationContext(target: legacyTarget, scenario: scenario)
        let optimized = HeuristicPromptOptimizer.optimize(trimmed, context: context)
        let heuristicText = optimized.optimizedText.trimmingCharacters(in: .whitespacesAndNewlines)

        let heuristicChangedSubstantially =
            heuristicText.count >= trimmed.count + 48 &&
            heuristicText.lowercased() != trimmed.lowercased()

        let built: String
        let note: String
        if mixMode == .shaken || !heuristicChangedSubstantially {
            let structured = OfflinePromptOptimizer().optimize(
                OptimizationInput(
                    rawUserPrompt: heuristicChangedSubstantially ? heuristicText : trimmed,
                    modelFamily: modelFamily,
                    scenario: scenario,
                    userOverrides: ir.intentKind == .structuredOutput ? UserOverrideOptions(strictJSONOverride: true) : nil
                )
            ).optimizedPrompt
            built = structured
            note = mixMode == .shaken
                ? "Applied full Shaken target engineering + constraint & output structure for \(recipe.modelID)"
                : "Restructured draft with \(recipe.modelID) goal, execution guidelines, and verification structure"
        } else {
            built = heuristicText
            note = "Applied Heuristic Optimization (\(optimized.selectedCandidateTitle))"
        }

        let resolved = applyExplicitVariables(built, values: variables, resolver: resolver)
        let guarded = appendMissingProtectedTokens(to: resolved, ir: ir, negativePrompt: nil)
        return (guarded, note)
    }
}
