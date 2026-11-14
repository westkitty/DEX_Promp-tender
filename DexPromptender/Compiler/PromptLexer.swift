import Foundation

/// Source-preserving lexer that extracts protected spans, tokens, counts, and structure
/// from raw user drafts using UTF-16 NSRange anchoring without altering the input string.
final class PromptLexer {
    private struct PatternRule {
        let kind: ProtectedSpanKind
        let regex: NSRegularExpression
        let payloadGroup: Int
    }

    private let rules: [PatternRule]

    init() {
        let specs: [(ProtectedSpanKind, String, NSRegularExpression.Options, Int)] = [
            (.codeFence, #"```[\s\S]*?```"#, [], 0),
            (.inlineCode, #"`[^`\n]+`"#, [], 0),
            (.explicitLock, #"(?im)\b(?:lock|keep|exact)\s*:\s*([^\n;]+)|\[LOCK\]([\s\S]*?)\[/LOCK\]"#, [], 1),
            (.negativeDirective, #"(?im)(?:^|[\s,;])(?:NOT|DO\s+NOT)\s*:\s*([^\n]+)|(?:^|\s)--no\s+([^\n]+)"#, [], 1),
            (.loraOrLyco, #"<(?:lora|lyco|hypernet):[^>]+>"#, [.caseInsensitive], 0),
            (.videoReference, #"<(?:VIDEO|IMAGE)_REF_\d+>|\[(?:VIDEO|IMAGE)_REF_\d+\]|(?<!\w)@(?:video|image|ref|voice)\d+\b"#, [.caseInsensitive], 0),
            (.wildcard, #"__[A-Za-z0-9_./-]+__"#, [], 0),
            (.templateVariable, #"\{([A-Za-z0-9_\-]+)\}"#, [], 1),
            (.embedding, #"\bembedding:[A-Za-z0-9_.-]+\b"#, [.caseInsensitive], 0),
            (.qualityScoreTag, #"\b(?:score_(?:[0-9]|up|down)|source_(?:anime|cartoon|furry|pony|western)|rating_(?:safe|questionable|explicit))[A-Za-z0-9_]*\b"#, [.caseInsensitive], 0),
            (.timestampCue, #"(?:\[\s*\d{1,2}:\d{2}(?:\.\d+)?\s*(?:-|to|->|–)\s*\d{1,2}:\d{2}(?:\.\d+)?\s*\])|(?:\b\d{1,2}:\d{2}\s*(?:-|to|->|–)\s*\d{1,2}:\d{2}\b)"#, [.caseInsensitive], 0),
            (.audioStructureTag, #"\[(?:Intro|Verse(?:\s*\d+)?|Pre-Chorus|Chorus|Bridge|Outro|Hook|SFX\s*:[^\]]+|Dialogue\s*:[^\]]+|Voiceover\s*:[^\]]+|Ambient\s*:[^\]]+|Audio\s*:[^\]]+)\]"#, [.caseInsensitive], 0),
            (.url, #"https?://[^\s<>()\"\']+"#, [.caseInsensitive], 0),
            (.filePath, #"(?:(?<=^)|(?<=[\s(\"\']))(?:~|/|\./)[A-Za-z0-9_.\-/']+"#, [], 0),
            (.quotedLiteral, #"\"([^\"\n]{2,180})\""#, [], 1),
            (.numericConstraint, #"(?i)\b(?:\d{2,5}\s*[x×]\s*\d{2,5}|\d{1,2}:\d{1,2}|\d+(?:\.\d+)?\s*(?:seconds?|secs?|s|fps|mm|k)|f/\d+(?:\.\d+)?|(?:\d+|two|three|four|five|six|seven|eight|nine|ten)\s+(?:separate\s+)?[A-Za-z][A-Za-z\-]{2,})\b"#, [], 0)
        ]

        self.rules = specs.compactMap { kind, pattern, options, payloadGroup in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
                return nil
            }
            return PatternRule(kind: kind, regex: regex, payloadGroup: payloadGroup)
        }
    }

    func lex(_ input: String) -> PromptLexResult {
        let fullRange = NSRange(input.startIndex..<input.endIndex, in: input)
        let nsInput = input as NSString
        var accepted: [ProtectedSpan] = []

        for rule in rules {
            let matches = rule.regex.matches(in: input, options: [], range: fullRange)
            for match in matches {
                let matchRange = match.range
                guard matchRange.location != NSNotFound, matchRange.length > 0 else { continue }
                // Highest-precedence rules run first; avoid overlapping double-captures except
                // letting variables inside URLs/paths stay covered by the outer URL/path.
                if overlapsAny(matchRange, existing: accepted) {
                    continue
                }
                let matchedText = nsInput.substring(with: matchRange)
                let payload = extractPayload(from: match, nsInput: nsInput, fallback: matchedText, preferredGroup: rule.payloadGroup)
                let line = lineNumber(atUTF16Offset: matchRange.location, in: nsInput)
                accepted.append(
                    ProtectedSpan(
                        kind: rule.kind,
                        text: matchedText,
                        normalizedPayload: payload,
                        utf16Location: matchRange.location,
                        utf16Length: matchRange.length,
                        lineNumber: line
                    )
                )
            }
        }

        accepted.sort { $0.utf16Location < $1.utf16Location }

        var variables: [String] = []
        var wildcards: [String] = []
        var loras: [String] = []
        var videoRefs: [String] = []
        var quotedLiterals: [String] = []

        for span in accepted {
            switch span.kind {
            case .templateVariable:
                appendUnique(span.normalizedPayload, to: &variables)
            case .wildcard:
                appendUnique(span.text, to: &wildcards)
            case .loraOrLyco, .embedding:
                appendUnique(span.text, to: &loras)
            case .videoReference:
                appendUnique(span.text, to: &videoRefs)
            case .quotedLiteral:
                appendUnique(span.normalizedPayload, to: &quotedLiterals)
            default:
                break
            }
        }

        let subjectCounts = extractSubjectCounts(in: input, excludingCodeRanges: accepted.filter {
            $0.kind == .codeFence || $0.kind == .inlineCode
        }.map { $0.nsRange })

        return PromptLexResult(
            rawInput: input,
            spans: accepted,
            variables: variables,
            wildcards: wildcards,
            loras: loras,
            videoRefs: videoRefs,
            quotedLiterals: quotedLiterals,
            subjectCounts: subjectCounts
        )
    }

    private func overlapsAny(_ candidate: NSRange, existing: [ProtectedSpan]) -> Bool {
        let cStart = candidate.location
        let cEnd = candidate.location + candidate.length
        for span in existing {
            let eStart = span.utf16Location
            let eEnd = span.utf16Location + span.utf16Length
            if cStart < eEnd && cEnd > eStart {
                return true
            }
        }
        return false
    }

    private func extractPayload(
        from match: NSTextCheckingResult,
        nsInput: NSString,
        fallback: String,
        preferredGroup: Int
    ) -> String {
        if preferredGroup > 0 && preferredGroup < match.numberOfRanges {
            for idx in 1..<match.numberOfRanges {
                let r = match.range(at: idx)
                if r.location != NSNotFound && r.length > 0 {
                    return nsInput.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func lineNumber(atUTF16Offset offset: Int, in nsInput: NSString) -> Int {
        guard offset > 0 else { return 1 }
        let prefix = nsInput.substring(to: min(offset, nsInput.length))
        return prefix.reduce(into: 1) { count, ch in
            if ch == "\n" { count += 1 }
        }
    }

    private func appendUnique(_ value: String, to list: inout [String]) {
        guard !value.isEmpty, !list.contains(value) else { return }
        list.append(value)
    }

    private func extractSubjectCounts(in text: String, excludingCodeRanges: [NSRange]) -> [SubjectCountRequirement] {
        let wordNumbers: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "pair": 2, "trio": 3, "quartet": 4
        ]
        let ignoredUnits: Set<String> = [
            "second", "seconds", "sec", "secs", "minute", "minutes", "min", "mins",
            "hour", "hours", "step", "steps", "pixel", "pixels", "px", "fps", "mm",
            "percent", "line", "lines", "file", "files", "item", "items", "part", "parts",
            "times", "way", "ways", "day", "days", "week", "weeks", "year", "years", "version"
        ]
        let pattern = #"(?i)\b(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|pair\s+of|trio\s+of|quartet\s+of)\s+(?:(separate|distinct|individual|different)\s+)?([A-Za-z][A-Za-z\-]{1,}(?:\s+(?:of\s+)?[A-Za-z][A-Za-z\-]{2,}){0,3}?)(?=\s*(?:[,.;\n]|$|\b(?:with|in|on|at|from|wearing|holding|under|beside|not|without|avoid)\b))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let nsText = text as NSString
        var results: [SubjectCountRequirement] = []
        var seenKeys = Set<String>()

        for match in regex.matches(in: text, options: [], range: fullRange) {
            let fullMatch = match.range
            if excludingCodeRanges.contains(where: { $0.location < fullMatch.location + fullMatch.length && ($0.location + $0.length) > fullMatch.location }) {
                continue
            }
            let rawCount = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedWord = rawCount.lowercased().replacingOccurrences(of: " of", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let numericCount = Int(normalizedWord) ?? wordNumbers[normalizedWord] ?? 0
            guard numericCount >= 1 else { continue }

            let qualifierRange = match.range(at: 2)
            let qualifier = qualifierRange.location != NSNotFound ? nsText.substring(with: qualifierRange) + " " : ""
            let entity = nsText.substring(with: match.range(at: 3))
            if ignoredUnits.contains(entity.lowercased()) {
                continue
            }
            let combinedEntity = (qualifier + entity).trimmingCharacters(in: .whitespacesAndNewlines)
            let dedupKey = "\(numericCount):\(combinedEntity.lowercased())"
            if seenKeys.insert(dedupKey).inserted {
                results.append(SubjectCountRequirement(count: numericCount, rawCountToken: rawCount, entity: combinedEntity))
            }
        }
        return results
    }
}
