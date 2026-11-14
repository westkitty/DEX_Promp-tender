import Foundation

struct InvariantViolation: Identifiable, Equatable, Codable {
    let id: UUID
    let invariant: SemanticInvariant
    let reason: String

    init(id: UUID = UUID(), invariant: SemanticInvariant, reason: String) {
        self.id = id
        self.invariant = invariant
        self.reason = reason
    }
}

struct InvariantVerificationResult: Equatable, Codable {
    let passedInvariants: [SemanticInvariant]
    let violations: [InvariantViolation]

    var isClean: Bool { violations.isEmpty }
}

/// Validates that target compilation and enhancement never silently drop, weaken,
/// or contradict user-authored literals, counts, exclusions, or asset bindings.
final class InvariantRegistry {
    func verify(
        ir: CanonicalPromptIR,
        compiledPrompt: String,
        negativePrompt: String?,
        structuredPayloadJSON: String,
        systemInstructions: String? = nil
    ) -> InvariantVerificationResult {
        var passed: [SemanticInvariant] = []
        var violations: [InvariantViolation] = []

        let combinedOutput = [
            compiledPrompt,
            negativePrompt ?? "",
            systemInstructions ?? "",
            structuredPayloadJSON
        ].joined(separator: "\n")
        let lowerCombined = combinedOutput.lowercased()
        let lowerPositive = compiledPrompt.lowercased()

        for invariant in ir.invariants where invariant.isEnabled {
            switch invariant.kind {
            case .preserveProtectedSpan, .preserveTextLiteral:
                let required = invariant.requiredToken
                if combinedOutput.contains(required) || (invariant.kind == .preserveProtectedSpan && containsNormalizedWildcardOrVariable(required, in: combinedOutput)) {
                    passed.append(invariant)
                } else {
                    violations.append(
                        InvariantViolation(
                            invariant: invariant,
                            reason: "Protected token \"\(required)\" was dropped or modified during compilation."
                        )
                    )
                }

            case .preserveSubjectCount:
                let token = invariant.requiredToken
                if matchesSubjectCount(token: token, in: combinedOutput) {
                    passed.append(invariant)
                } else {
                    violations.append(
                        InvariantViolation(
                            invariant: invariant,
                            reason: "Subject multiplicity requirement \"\(token)\" is no longer explicitly preserved."
                        )
                    )
                }

            case .preserveExclusion:
                let exclusion = invariant.requiredToken.lowercased()
                let negLower = (negativePrompt ?? "").lowercased()
                if negLower.contains(exclusion) || lowerCombined.contains(exclusion) {
                    passed.append(invariant)
                } else {
                    violations.append(
                        InvariantViolation(
                            invariant: invariant,
                            reason: "Exclusion \"\(invariant.requiredToken)\" was omitted from output and negative prompt."
                        )
                    )
                }

            case .forbidCollageMerge:
                if containsAffirmativeCollageInjection(in: lowerPositive) {
                    violations.append(
                        InvariantViolation(
                            invariant: invariant,
                            reason: "Output injected collage/grid framing even though separate individual images were requested."
                        )
                    )
                } else if lowerCombined.contains("separate") || lowerCombined.contains("individual") || lowerCombined.contains("distinct") || (negativePrompt ?? "").lowercased().contains("collage") {
                    passed.append(invariant)
                } else {
                    violations.append(
                        InvariantViolation(
                            invariant: invariant,
                            reason: "Separate-image requirement was weakened and no longer specifies individual outputs."
                        )
                    )
                }

            case .preserveReferenceBinding:
                if lowerCombined.contains(invariant.requiredToken.lowercased()) {
                    passed.append(invariant)
                } else {
                    violations.append(
                        InvariantViolation(
                            invariant: invariant,
                            reason: "Attached reference asset \"\(invariant.requiredToken)\" is not bound in compiled payload."
                        )
                    )
                }
            }
        }

        return InvariantVerificationResult(passedInvariants: passed, violations: violations)
    }

    private func containsNormalizedWildcardOrVariable(_ token: String, in output: String) -> Bool {
        output.localizedCaseInsensitiveContains(token)
    }

    private func matchesSubjectCount(token: String, in output: String) -> Bool {
        let lowerOutput = output.lowercased()
        if lowerOutput.contains(token.lowercased()) {
            return true
        }
        // Allow numeric/word equivalence ("3" <-> "three", preserving entity).
        let parts = token.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        let countToken = parts[0].lowercased()
        let entity = parts[1].lowercased()
        let equivalents: [String: String] = [
            "1": "one", "one": "1",
            "2": "two", "two": "2",
            "3": "three", "three": "3",
            "4": "four", "four": "4",
            "5": "five", "five": "5",
            "6": "six", "six": "6",
            "7": "seven", "seven": "7",
            "8": "eight", "eight": "8",
            "9": "nine", "nine": "9",
            "10": "ten", "ten": "10"
        ]
        if let alt = equivalents[countToken], lowerOutput.contains("\(alt) \(entity)") {
            return true
        }
        return false
    }

    private func containsAffirmativeCollageInjection(in lowerPositive: String) -> Bool {
        let collageTerms = ["collage", "contact sheet", "grid layout", "quad-split", "split panel", "montage grid"]
        for term in collageTerms {
            guard let range = lowerPositive.range(of: term) else { continue }
            let prefixStart = lowerPositive.index(range.lowerBound, offsetBy: -18, limitedBy: lowerPositive.startIndex) ?? lowerPositive.startIndex
            let prefixWindow = String(lowerPositive[prefixStart..<range.lowerBound])
            let negated = prefixWindow.contains("no ") || prefixWindow.contains("not ") || prefixWindow.contains("without ") || prefixWindow.contains("never ") || prefixWindow.contains("avoid ")
            if !negated {
                return true
            }
        }
        return false
    }
}
