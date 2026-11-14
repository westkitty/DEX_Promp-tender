import Foundation

enum IngredientChangeStatus: String, Codable, Hashable {
    case preserved = "preserved"
    case restructured = "restructured"
    case movedToSlot = "moved_to_slot"
    case expanded = "expanded"
}

struct SemanticDiffItem: Identifiable, Equatable, Codable {
    let id: UUID
    let ingredientName: String
    let beforeSummary: String
    let afterSummary: String
    let status: IngredientChangeStatus
    let attribution: ProvenanceSource

    init(
        id: UUID = UUID(),
        ingredientName: String,
        beforeSummary: String,
        afterSummary: String,
        status: IngredientChangeStatus,
        attribution: ProvenanceSource
    ) {
        self.id = id
        self.ingredientName = ingredientName
        self.beforeSummary = beforeSummary
        self.afterSummary = afterSummary
        self.status = status
        self.attribution = attribution
    }
}

struct SemanticDiffReport: Equatable {
    let lineDiffs: [DiffLine]
    let ingredientChanges: [SemanticDiffItem]
    let preservedLockCount: Int
    let violatedLockCount: Int
    let additionsCount: Int

    var summaryHeadline: String {
        if violatedLockCount > 0 {
            return "\(preservedLockCount) locks kept · \(violatedLockCount) violated · \(additionsCount) target additions"
        }
        return "\(preservedLockCount) locks kept · \(ingredientChanges.count) structured transforms · \(additionsCount) target additions"
    }
}

final class SemanticDiffEngine {
    func buildDiff(
        ir: CanonicalPromptIR,
        compiledPrompt: String,
        negativePrompt: String?,
        structuredPayloadJSON: String,
        provenance: [ProvenanceEntry],
        invariantResult: InvariantVerificationResult
    ) -> SemanticDiffReport {
        let lineDiffs = TextDiffEngine().diff(old: ir.rawInput, new: compiledPrompt)
        var items: [SemanticDiffItem] = []

        if !ir.ingredients.subject.isEmpty {
            items.append(
                SemanticDiffItem(
                    ingredientName: "Core Subject / Intent",
                    beforeSummary: ir.ingredients.subject,
                    afterSummary: firstNonEmptyLine(compiledPrompt),
                    status: compiledPrompt.contains(ir.ingredients.subject) ? .preserved : .restructured,
                    attribution: .userAuthored
                )
            )
        }

        if !ir.ingredients.negativeIntent.isEmpty {
            let negList = ir.ingredients.negativeIntent.joined(separator: ", ")
            if let negPrompt = negativePrompt, !negPrompt.isEmpty {
                items.append(
                    SemanticDiffItem(
                        ingredientName: "Exclusions",
                        beforeSummary: negList,
                        afterSummary: "negative_prompt: \(negPrompt)",
                        status: .movedToSlot,
                        attribution: .deterministicParser
                    )
                )
            } else {
                items.append(
                    SemanticDiffItem(
                        ingredientName: "Exclusions",
                        beforeSummary: negList,
                        afterSummary: "Integrated as explicit constraint prose",
                        status: .restructured,
                        attribution: .providerProfile
                    )
                )
            }
        }

        if !ir.ingredients.temporalTimeline.isEmpty {
            items.append(
                SemanticDiffItem(
                    ingredientName: "Temporal Timeline",
                    beforeSummary: "\(ir.ingredients.temporalTimeline.count) authored beat(s)",
                    afterSummary: "Sequenced chronological timeline preserved in prompt & JSON payload",
                    status: .restructured,
                    attribution: .deterministicParser
                )
            )
        }

        if !ir.ingredients.referenceAssets.isEmpty {
            items.append(
                SemanticDiffItem(
                    ingredientName: "Reference Assets",
                    beforeSummary: ir.ingredients.referenceAssets.map { "\($0.role.displayName): \($0.label)" }.joined(separator: ", "),
                    afterSummary: "Bound into target payload reference slots",
                    status: .movedToSlot,
                    attribution: .providerProfile
                )
            )
        }

        for entry in provenance where entry.source == .providerProfile || entry.source == .heuristicTransform || entry.source == .embeddedTinyLLM {
            items.append(
                SemanticDiffItem(
                    ingredientName: entry.section,
                    beforeSummary: "Not explicit in draft",
                    afterSummary: entry.note,
                    status: .expanded,
                    attribution: entry.source
                )
            )
        }

        let additions = items.filter { $0.status == .expanded }.count

        return SemanticDiffReport(
            lineDiffs: lineDiffs,
            ingredientChanges: items,
            preservedLockCount: invariantResult.passedInvariants.count,
            violatedLockCount: invariantResult.violations.count,
            additionsCount: additions
        )
    }

    private func firstNonEmptyLine(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }
}
