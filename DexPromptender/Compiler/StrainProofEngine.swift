import Foundation

/// Validates compiled output, payload structure, invariants, parameters, and target readiness.
/// Never invents fabricated numerical quality percentages.
final class StrainProofEngine {
    private let invariantRegistry: InvariantRegistry

    init(invariantRegistry: InvariantRegistry = InvariantRegistry()) {
        self.invariantRegistry = invariantRegistry
    }

    func validate(
        ir: CanonicalPromptIR,
        recipe: RecipeProfile,
        compiledPrompt: String,
        negativePrompt: String?,
        systemInstructions: String?,
        structuredPayloadJSON: String,
        resolvedParameters: TechnicalParameterSet,
        readiness: ReadinessState
    ) -> ProofReport {
        var items: [ProofItem] = []

        // 1. Non-empty compiled prompt
        let trimmedCompiled = compiledPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCompiled.isEmpty {
            items.append(
                ProofItem(
                    severity: .blocking,
                    category: "Output",
                    title: "Compiled prompt is empty",
                    detail: "No compilable instruction was produced for \(recipe.name).",
                    remediation: "Enter a clear subject, action, or task before serving."
                )
            )
        } else {
            items.append(
                ProofItem(
                    severity: .pass,
                    category: "Output",
                    title: "Non-empty target instruction compiled",
                    detail: "Produced \(trimmedCompiled.count) characters formatted for \(recipe.modelID)."
                )
            )
        }

        // 2. Semantic Invariants
        let invariantCheck = invariantRegistry.verify(
            ir: ir,
            compiledPrompt: compiledPrompt,
            negativePrompt: negativePrompt,
            structuredPayloadJSON: structuredPayloadJSON,
            systemInstructions: systemInstructions
        )
        if invariantCheck.violations.isEmpty {
            items.append(
                ProofItem(
                    severity: .pass,
                    category: "Invariants",
                    title: "All semantic locks & protected tokens preserved",
                    detail: "\(invariantCheck.passedInvariants.count) invariant(s) verified without alteration."
                )
            )
        } else {
            for violation in invariantCheck.violations {
                items.append(
                    ProofItem(
                        severity: .blocking,
                        category: "Invariants",
                        title: "Invariant violated: \(violation.invariant.label)",
                        detail: violation.reason,
                        remediation: "Switch Mix Mode to Neat or inspect protected locks."
                    )
                )
            }
        }

        // 3. Target Character Ceiling (e.g. DexDiffusion generation-job.schema.json maxLength: 4000)
        if let maxChars = recipe.constraints.maxPromptCharacters {
            if trimmedCompiled.count > maxChars {
                items.append(
                    ProofItem(
                        severity: .blocking,
                        category: "Length Limit",
                        title: "Prompt exceeds target maximum (\(trimmedCompiled.count) / \(maxChars) chars)",
                        detail: "\(recipe.name) enforces a strict \(maxChars)-character limit.",
                        remediation: "Shorten verbose context or switch Mix Mode to Neat/Stirred."
                    )
                )
            } else {
                items.append(
                    ProofItem(
                        severity: .pass,
                        category: "Length Limit",
                        title: "Within target character budget (\(trimmedCompiled.count) / \(maxChars) chars)",
                        detail: "Safe margin: \(maxChars - trimmedCompiled.count) characters remaining."
                    )
                )
            }
        }

        if let maxNeg = recipe.constraints.maxNegativeCharacters, let neg = negativePrompt, neg.count > maxNeg {
            items.append(
                ProofItem(
                    severity: .blocking,
                    category: "Negative Length",
                    title: "Negative prompt exceeds target limit (\(neg.count) / \(maxNeg) chars)",
                    detail: "DexDiffusion schema restricts negative_prompt to \(maxNeg) characters.",
                    remediation: "Trim duplicate negative descriptors."
                )
            )
        }

        // 4. Negative-in-positive diffusion check
        if recipe.destination.isImageTarget || recipe.destination.isVideoTarget {
            let lowerPos = trimmedCompiled.lowercased()
            let hasBareNoFlag = lowerPos.contains(" --no ") || lowerPos.hasPrefix("--no ")
            if hasBareNoFlag {
                items.append(
                    ProofItem(
                        severity: .blocking,
                        category: "Syntax",
                        title: "Unsupported CLI `--no` flag in compiled prompt",
                        detail: "\(recipe.name) does not parse Midjourney `--no` flags natively.",
                        remediation: "Move exclusions into the dedicated Negative / Exclusion section."
                    )
                )
            }
            if recipe.destination == .dexDiffusionImage && recipe.modelID.contains("flux") {
                if let neg = negativePrompt, !neg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    items.append(
                        ProofItem(
                            severity: .warning,
                            category: "Model Dialect",
                            title: "FLUX targets rely minimally on negative_prompt",
                            detail: "Positive phrasing of what SHOULD appear works more reliably than heavy negative tags on FLUX.",
                            remediation: "Express critical visual absences in positive compositional terms when possible."
                        )
                    )
                }
            }
        }

        // 5. Reference asset count & role checks
        let refs = ir.ingredients.referenceAssets
        if !refs.isEmpty {
            let maxRefs = recipe.constraints.maxReferenceAssets
            if refs.count > maxRefs {
                items.append(
                    ProofItem(
                        severity: .blocking,
                        category: "References",
                        title: "Too many reference assets (\(refs.count) / max \(maxRefs))",
                        detail: "\(recipe.name) supports at most \(maxRefs) reference image(s).",
                        remediation: "Remove \(refs.count - maxRefs) reference asset(s) before submitting."
                    )
                )
            } else {
                items.append(
                    ProofItem(
                        severity: .pass,
                        category: "References",
                        title: "Reference assets within limit (\(refs.count) / \(maxRefs))",
                        detail: refs.map { "\($0.role.displayName): \($0.label)" }.joined(separator: ", ")
                    )
                )
            }

            let voiceRefs = refs.filter { $0.role == .voice }
            if voiceRefs.count > recipe.constraints.maxVoiceReferences {
                items.append(
                    ProofItem(
                        severity: .blocking,
                        category: "Audio Refs",
                        title: "Voice reference count exceeds target limit (\(voiceRefs.count) / \(recipe.constraints.maxVoiceReferences))",
                        detail: "\(recipe.name) accepts at most \(recipe.constraints.maxVoiceReferences) voice reference(s).",
                        remediation: "Trim extra voice references."
                    )
                )
            }

            if refs.contains(where: { $0.role == .mask }) && !recipe.constraints.supportsMaskEditing {
                items.append(
                    ProofItem(
                        severity: .blocking,
                        category: "Editing",
                        title: "Edit mask attached to non-mask target",
                        detail: "\(recipe.name) does not accept an explicit binary mask slot.",
                        remediation: "Switch to OpenAI GPT Image (`/v1/images/edits`) or remove the mask asset."
                    )
                )
            }
        }

        // 6. Aspect ratio, resolution, duration checks
        if let ar = resolvedParameters.aspectRatio, !recipe.constraints.supportedAspectRatios.isEmpty {
            if !recipe.constraints.supportedAspectRatios.contains(ar) {
                items.append(
                    ProofItem(
                        severity: .blocking,
                        category: "Parameters",
                        title: "Unsupported aspect ratio \(ar)",
                        detail: "\(recipe.name) supports: \(recipe.constraints.supportedAspectRatios.joined(separator: ", ")).",
                        remediation: "Pick a supported aspect ratio in Parameters."
                    )
                )
            } else {
                items.append(
                    ProofItem(
                        severity: .pass,
                        category: "Parameters",
                        title: "Aspect ratio \(ar) validated",
                        detail: "Matches \(recipe.modelID) allowed geometry."
                    )
                )
            }
        }

        if let res = resolvedParameters.resolutionTier, !recipe.constraints.supportedResolutions.isEmpty {
            if !recipe.constraints.supportedResolutions.contains(where: { $0.caseInsensitiveCompare(res) == .orderedSame }) {
                items.append(
                    ProofItem(
                        severity: .warning,
                        category: "Resolution",
                        title: "Resolution \(res) differs from target presets",
                        detail: "\(recipe.name) natively documents: \(recipe.constraints.supportedResolutions.joined(separator: ", "))."
                    )
                )
            }
        }

        if recipe.destination.isVideoTarget {
            if let dur = resolvedParameters.durationSeconds {
                if let maxDur = recipe.constraints.maxDurationSeconds, dur > maxDur {
                    items.append(
                        ProofItem(
                            severity: .blocking,
                            category: "Video Duration",
                            title: "Duration \(String(format: "%.1fs", dur)) exceeds target cap (\(Int(maxDur))s)",
                            detail: "\(recipe.name) limits single-clip generation to \(Int(maxDur)) seconds.",
                            remediation: "Split into chained clips or cap duration at \(Int(maxDur))s."
                        )
                    )
                } else if let minDur = recipe.constraints.minDurationSeconds, dur < minDur {
                    items.append(
                        ProofItem(
                            severity: .warning,
                            category: "Video Duration",
                            title: "Duration \(String(format: "%.1fs", dur)) below recommended minimum (\(Int(minDur))s)",
                            detail: "Shorter clips may compress motion continuity."
                        )
                    )
                } else {
                    items.append(
                        ProofItem(
                            severity: .pass,
                            category: "Video Duration",
                            title: "Video duration \(String(format: "%.1fs", dur)) within bounds",
                            detail: "Compliant with \(recipe.modelID) runtime range."
                        )
                    )
                }
            }

            if ir.ingredients.temporalTimeline.isEmpty {
                items.append(
                    ProofItem(
                        severity: .warning,
                        category: "Temporal Structure",
                        title: "No explicit multi-beat timeline in source draft",
                        detail: "Video models maintain cleaner motion continuity when start/mid/end actions or camera movement are specified.",
                        remediation: "Use `[00:00-00:04]` beat lines or camera trajectory cues."
                    )
                )
            } else {
                items.append(
                    ProofItem(
                        severity: .pass,
                        category: "Temporal Structure",
                        title: "Temporal beat sequence preserved (\(ir.ingredients.temporalTimeline.count) beats)",
                        detail: "Start-to-end continuity and motion ordering encoded for video generation."
                    )
                )
            }
        }

        // 7. Unresolved variables warning (never silently drop or guess)
        if !ir.lexResult.variables.isEmpty {
            let stillUnfilled = ir.lexResult.variables.filter { trimmedCompiled.contains("{\($0)}") }
            if !stillUnfilled.isEmpty {
                items.append(
                    ProofItem(
                        severity: .warning,
                        category: "Variables",
                        title: "Unfilled template variable(s): \(stillUnfilled.map { "{\($0)}" }.joined(separator: ", "))",
                        detail: "Preserved verbatim as placeholders so no intent was guessed.",
                        remediation: "Fill variable values before sending to an external model."
                    )
                )
            }
        }

        // 8. Readiness note
        switch readiness {
        case .blocked(let reason):
            items.append(
                ProofItem(
                    severity: .warning,
                    category: "Runtime Readiness",
                    title: "Prompt ready locally; live submission blocked (\(reason))",
                    detail: "Copy/export prompt workflows work offline without restrictions."
                )
            )
        case .sourceImplemented, .unknown:
            items.append(
                ProofItem(
                    severity: .warning,
                    category: "Runtime Readiness",
                    title: "Target live runtime state is \(readiness.badgeLabel)",
                    detail: "Local compilation is verified; live API execution requires connectivity/configuration."
                )
            )
        default:
            items.append(
                ProofItem(
                    severity: .pass,
                    category: "Runtime Readiness",
                    title: "Target status: \(readiness.badgeLabel)",
                    detail: "Verified against active capability state."
                )
            )
        }

        // 9. Valid JSON payload check
        if let jsonData = structuredPayloadJSON.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: jsonData)) != nil {
            items.append(
                ProofItem(
                    severity: .pass,
                    category: "API Schema",
                    title: "Structured target JSON payload is valid",
                    detail: "Ready for inspection, clipboard copy, or opt-in submission."
                )
            )
        } else {
            items.append(
                ProofItem(
                    severity: .blocking,
                    category: "API Schema",
                    title: "Structured JSON serialization failed",
                    detail: "Could not produce valid JSON for \(recipe.modelID)."
                )
            )
        }

        return ProofReport(
            items: items,
            characterCount: trimmedCompiled.count,
            characterLimit: recipe.constraints.maxPromptCharacters
        )
    }
}
