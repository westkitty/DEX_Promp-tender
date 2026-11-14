import Foundation
import NaturalLanguage

/// Deterministic parser building CanonicalPromptIR from raw user input, variables,
/// reference assets, and parameter overrides without mutating the source string.
final class SemanticIRParser {
    private let lexer: PromptLexer

    init(lexer: PromptLexer = PromptLexer()) {
        self.lexer = lexer
    }

    func parse(
        rawInput: String,
        hintedIntent: IntentKind? = nil,
        attachedAssets: [ReferenceAsset] = [],
        parameterOverrides: TechnicalParameterSet = TechnicalParameterSet(),
        manualLocks: [String] = []
    ) -> CanonicalPromptIR {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let lexResult = lexer.lex(rawInput)
        let intentKind = hintedIntent ?? inferIntent(from: trimmed, lexResult: lexResult, attachedAssets: attachedAssets)

        var ingredients = PromptIngredients()
        ingredients.referenceAssets = attachedAssets

        let lines = rawInput
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)

        var positiveLines: [String] = []
        var negativeItems: [String] = []
        var constraintItems: [String] = []
        var spatialItems: [String] = []
        var deliverableItems: [String] = []
        let outputContractItems: [String] = []
        var continuityItems: [String] = []

        var detectedBeats: [VideoBeat] = []
        var spokenDialogue: [String] = []
        var soundEffects: [String] = []
        var ambientAudioParts: [String] = []
        var styleParts: [String] = []
        var cameraParts: [String] = []
        var lightingParts: [String] = []

        var inCodeFence = false
        for rawLine in lines {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.hasPrefix("```") {
                inCodeFence.toggle()
                positiveLines.append(rawLine)
                continue
            }
            if inCodeFence {
                positiveLines.append(rawLine)
                continue
            }
            if trimmedLine.isEmpty { continue }

            let lower = trimmedLine.lowercased()

            // Negative directives (prefix NOT:, DO NOT:, Negative:, Avoid:, Without:, --no)
            if let extractedNegative = extractPrefixedValue(
                from: trimmedLine,
                prefixes: ["not:", "do not:", "negative:", "negative prompt:", "exclude:", "--no "]
            ) {
                splitCommaOrSemicolonList(extractedNegative).forEach { appendUnique($0, to: &negativeItems) }
                continue
            }

            // Explicit inline locks
            if let lockedValue = extractPrefixedValue(from: trimmedLine, prefixes: ["lock:", "keep:", "exact:"]) {
                appendUnique(lockedValue, to: &constraintItems)
                positiveLines.append(lockedValue)
                continue
            }

            // Temporal beat / shot parsing
            if let beat = parseVideoBeatLine(trimmedLine, index: detectedBeats.count + 1) {
                detectedBeats.append(beat)
                if !beat.audioCue.isEmpty {
                    appendUnique(beat.audioCue, to: &soundEffects)
                }
                continue
            }

            // Dialogue / SFX / Ambient audio lines
            if let speech = extractPrefixedValue(from: trimmedLine, prefixes: ["dialogue:", "speech:", "voiceover:", "says:", "speaks:"]) {
                let normalizedSpeech = speech.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'"))
                appendUnique(normalizedSpeech, to: &spokenDialogue)
                continue
            }
            if let sfx = extractPrefixedValue(from: trimmedLine, prefixes: ["sfx:", "sound:", "audio:"]) {
                appendUnique(sfx, to: &soundEffects)
                continue
            }
            if let ambient = extractPrefixedValue(from: trimmedLine, prefixes: ["ambient:", "ambience:", "music:"]) {
                appendUnique(ambient, to: &ambientAudioParts)
                continue
            }

            // Continuity & start/end frame lines
            if let continuity = extractPrefixedValue(from: trimmedLine, prefixes: ["continuity:", "start state:", "end state:", "starting frame:", "ending frame:"]) {
                appendUnique(trimmedLine, to: &continuityItems)
                positiveLines.append(continuity)
                continue
            }

            // Spatial & compositional lines
            if let spatial = extractPrefixedValue(from: trimmedLine, prefixes: ["spatial:", "layout:", "composition:", "framing:"]) {
                appendUnique(spatial, to: &spatialItems)
                continue
            }

            if let style = extractPrefixedValue(from: trimmedLine, prefixes: ["style:", "medium:", "aesthetic:"]) {
                appendUnique(style, to: &styleParts)
                continue
            }

            if let camera = extractPrefixedValue(from: trimmedLine, prefixes: ["camera:", "lens:", "shot:"]) {
                appendUnique(camera, to: &cameraParts)
                continue
            }

            if let lighting = extractPrefixedValue(from: trimmedLine, prefixes: ["lighting:", "mood:", "atmosphere:"]) {
                appendUnique(lighting, to: &lightingParts)
                continue
            }

            if lower.hasPrefix("constraint:") || lower.hasPrefix("constraints:") || lower.hasPrefix("must ") || lower.hasPrefix("never ") || lower.hasPrefix("only ") {
                let value = extractPrefixedValue(from: trimmedLine, prefixes: ["constraint:", "constraints:"]) ?? trimmedLine
                appendUnique(value, to: &constraintItems)
            }

            if let deliverable = extractPrefixedValue(from: trimmedLine, prefixes: ["deliverable:", "deliverables:", "output:"]) {
                appendUnique(deliverable, to: &deliverableItems)
                continue
            }

            positiveLines.append(trimmedLine)
        }

        // Inline negative extraction ("without X", "no watermark", "--no blur") inside narrative text
        for clause in extractInlineExclusions(from: positiveLines.joined(separator: "\n")) {
            appendUnique(clause, to: &negativeItems)
        }

        // Spatial cue extraction from narrative prose
        for cue in extractSpatialCues(from: trimmed) {
            appendUnique(cue, to: &spatialItems)
        }

        // Spoken lines inside video prompts ("says \"...\"" or dialogue quotes)
        if intentKind == .videoGeneration {
            for speechQuote in extractSpokenQuotes(from: trimmed) {
                appendUnique(speechQuote, to: &spokenDialogue)
            }
        }

        let joinedPositive = positiveLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryTuple = splitSubjectActionContext(from: joinedPositive, intentKind: intentKind)

        ingredients.subject = summaryTuple.subject
        ingredients.action = summaryTuple.action
        ingredients.sceneContext = summaryTuple.context
        ingredients.spatialRelations = spatialItems
        ingredients.styleMedium = styleParts.isEmpty ? inferStyleMedium(from: trimmed) : styleParts.joined(separator: ", ")
        ingredients.cameraComposition = cameraParts.isEmpty ? inferCameraCues(from: trimmed) : cameraParts.joined(separator: ", ")
        ingredients.lightingAtmosphere = lightingParts.isEmpty ? inferLightingCues(from: trimmed) : lightingParts.joined(separator: ", ")
        ingredients.constraints = constraintItems
        ingredients.negativeIntent = negativeItems
        ingredients.deliverables = deliverableItems
        ingredients.outputContract = outputContractItems
        ingredients.continuityAnchors = continuityItems
        ingredients.temporalTimeline = detectedBeats
        ingredients.separateOutputsRequested = detectSeparateOutputsRequest(in: trimmed)

        let lowerInput = trimmed.lowercased()
        let requiresLipSync = lowerInput.contains("lip sync") || lowerInput.contains("lip-sync") || lowerInput.contains("lipsync") || !spokenDialogue.isEmpty
        let suppressAudio = lowerInput.contains("silent video") || lowerInput.contains("no audio") || lowerInput.contains("without audio") || lowerInput.contains("mute audio")

        ingredients.audioDialogue = AudioCueSpec(
            spokenDialogue: spokenDialogue,
            soundEffects: soundEffects,
            ambientAudio: ambientAudioParts.joined(separator: ", "),
            requiresLipSync: requiresLipSync,
            suppressAudio: suppressAudio
        )

        ingredients.technicalParams = mergeParameters(
            inferred: inferTechnicalParameters(from: trimmed, beats: detectedBeats),
            overrides: parameterOverrides
        )

        let invariants = buildInvariants(
            lexResult: lexResult,
            ingredients: ingredients,
            manualLocks: manualLocks
        )

        return CanonicalPromptIR(
            rawInput: rawInput,
            lexResult: lexResult,
            intentKind: intentKind,
            ingredients: ingredients,
            invariants: invariants
        )
    }

    // MARK: - Intent Inference

    private func inferIntent(from text: String, lexResult: PromptLexResult, attachedAssets: [ReferenceAsset]) -> IntentKind {
        let lower = text.lowercased()

        if attachedAssets.contains(where: { $0.role == .mask || $0.role == .editSource }) ||
            lower.contains("inpaint") || lower.contains("remove the") && lower.contains("image") ||
            lower.contains("edit this photo") || lower.contains("edit the image") ||
            lower.contains("replace the background") || lower.contains("transparent background") {
            if !lower.contains("video") && !lower.contains("clip") {
                return .imageEdit
            }
        }

        if !lexResult.videoRefs.isEmpty ||
            !lexResult.spans(of: .timestampCue).isEmpty ||
            attachedAssets.contains(where: { $0.role == .videoClip || $0.role == .startFrame || $0.role == .endFrame || $0.role == .voice }) ||
            containsAny(lower, cues: ["video", "clip", "footage", "camera pan", "dolly", "tracking shot", "timelapse", "time-lapse", "frame transition", "lip sync", "lip-sync", "b-roll", "shot 1", "00:0"]) {
            return .videoGeneration
        }

        if containsAny(lower, cues: ["json schema", "return valid json", "structured json", "strict schema", "output format: json"]) {
            return .structuredOutput
        }

        if !lexResult.spans(of: .codeFence).isEmpty ||
            containsAny(lower, cues: ["swift", "typescript", "python", "refactor", "pull request", "unit test", "compile", "bug", "endpoint", "repository", "codebase", "regex", "sql", "api client"]) {
            return .codingAgent
        }

        if !lexResult.wildcards.isEmpty ||
            !lexResult.loras.isEmpty ||
            !lexResult.spans(of: .qualityScoreTag).isEmpty ||
            containsAny(lower, cues: ["photorealistic", "photograph", "illustration", "portrait", "concept art", "watercolor", "oil painting", "render", "cinematic still", "product photo", "poster", "logo", "sticker", "3d render", "aspect ratio", "flux", "sdxl", "grok imagine"]) {
            return .imageGeneration
        }

        if containsAny(lower, cues: ["research", "cite", "citations", "compare sources", "literature", "fact-check", "analyze", "benchmark"]) {
            return .researchAnalysis
        }

        return .generalText
    }

    // MARK: - Timeline & Beat Parsing

    private func parseVideoBeatLine(_ line: String, index: Int) -> VideoBeat? {
        // Matches: [00:00-00:04] ..., 00:04 -> 00:08: ..., Shot 1 (0-4s): ..., Beat 2: ...
        let timecodePattern = #"^(?:\[?\s*(\d{1,2}:\d{2}(?:\.\d+)?)\s*(?:-|to|->|–)\s*(\d{1,2}:\d{2}(?:\.\d+)?)\s*\]?|(?:Shot|Beat|Scene|Clip)\s*(\d+)(?:\s*\(([^)]+)\))?)\s*[:\-–]?\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: timecodePattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range) else { return nil }
        let nsLine = line as NSString

        var timeLabel = "Beat \(index)"
        var startSec: Double?
        var endSec: Double?
        if match.range(at: 1).location != NSNotFound && match.range(at: 2).location != NSNotFound {
            let s = nsLine.substring(with: match.range(at: 1))
            let e = nsLine.substring(with: match.range(at: 2))
            timeLabel = "\(s)–\(e)"
            startSec = parseTimecodeSeconds(s)
            endSec = parseTimecodeSeconds(e)
        } else if match.range(at: 3).location != NSNotFound {
            let shotNum = nsLine.substring(with: match.range(at: 3))
            if match.range(at: 4).location != NSNotFound {
                let extra = nsLine.substring(with: match.range(at: 4))
                timeLabel = "Shot \(shotNum) (\(extra))"
            } else {
                timeLabel = "Shot \(shotNum)"
            }
        }

        let body = nsLine.substring(with: match.range(at: 5)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        let camera = inferCameraCues(from: body)
        var audioCue = ""
        if let sfxMatch = body.range(of: #"(?i)\((?:audio|sfx|sound)\s*:\s*([^)]+)\)"#, options: .regularExpression) {
            audioCue = String(body[sfxMatch])
        }

        return VideoBeat(
            index: index,
            timecodeLabel: timeLabel,
            startSeconds: startSec,
            endSeconds: endSec,
            visualAction: body,
            cameraMotion: camera,
            audioCue: audioCue
        )
    }

    private func parseTimecodeSeconds(_ token: String) -> Double? {
        let parts = token.split(separator: ":")
        if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
            return (m * 60.0) + s
        }
        return Double(token)
    }

    // MARK: - Ingredient Extraction Helpers

    private func splitSubjectActionContext(from text: String, intentKind: IntentKind) -> (subject: String, action: String, context: String) {
        guard !text.isEmpty else { return ("", "", "") }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { sentences.append(s) }
            return true
        }
        if sentences.isEmpty {
            sentences = [text]
        }

        let first = sentences[0]
        let remaining = sentences.dropFirst().joined(separator: " ")

        switch intentKind {
        case .imageGeneration, .imageEdit, .videoGeneration:
            return (first, first, remaining)
        case .codingAgent, .researchAnalysis, .structuredOutput, .generalText:
            return (first, first, remaining)
        }
    }

    private func extractPrefixedValue(from line: String, prefixes: [String]) -> String? {
        let lower = line.lowercased()
        for prefix in prefixes {
            if lower.hasPrefix(prefix) {
                let start = line.index(line.startIndex, offsetBy: prefix.count)
                let rest = String(line[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return rest.isEmpty ? nil : rest
            }
        }
        return nil
    }

    private func splitCommaOrSemicolonList(_ value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func extractInlineExclusions(from text: String) -> [String] {
        let pattern = #"(?i)\b(?:without|avoid|no\s+added|exclude|never\s+include|do\s+not\s+include|do\s+not\s+add|must\s+not\s+contain)\s+([A-Za-z0-9_\-\s]{2,55})(?=[.,;\n]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let nsText = text as NSString
        var out: [String] = []
        for match in regex.matches(in: text, options: [], range: range) {
            guard match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else { continue }
            let item = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !item.isEmpty {
                out.append(item)
            }
        }
        return out
    }

    private func extractSpatialCues(from text: String) -> [String] {
        let pattern = #"(?i)\b(?:on the left|on the right|in the foreground|in the background|at the center|centered|side by side|side-by-side|facing left|facing right|looking away|over the shoulder|bird['’]?s[- ]eye|top-down|low-angle|eye-level|split screen|triptych|above|below|behind|beside)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let nsText = text as NSString
        var out: [String] = []
        for match in regex.matches(in: text, options: [], range: range) {
            appendUnique(nsText.substring(with: match.range), to: &out)
        }
        return out
    }

    private func extractSpokenQuotes(from text: String) -> [String] {
        let pattern = #"(?i)(?:says|speaks|whispers|shouts|narration|voiceover)\s*:?\s*\"([^\"\n]{2,200})\""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let nsText = text as NSString
        var out: [String] = []
        for match in regex.matches(in: text, options: [], range: range) {
            if match.range(at: 1).location != NSNotFound {
                appendUnique(nsText.substring(with: match.range(at: 1)), to: &out)
            }
        }
        return out
    }

    private func inferStyleMedium(from text: String) -> String {
        let candidates = [
            "photorealistic", "editorial photography", "35mm film", "medium format", "studio portrait",
            "oil painting", "watercolor", "ink illustration", "cel-shaded", "anime", "3d render",
            "unreal engine", "cyberpunk", "noir", "minimalist", "documentary", "stop motion", "pixel art"
        ]
        let lower = text.lowercased()
        return candidates.filter { lower.contains($0) }.joined(separator: ", ")
    }

    private func inferCameraCues(from text: String) -> String {
        let candidates = [
            "close-up", "closeup", "medium shot", "wide shot", "extreme wide", "macro", "telephoto",
            "24mm", "35mm", "50mm", "85mm", "f/1.4", "f/1.8", "f/2.8", "shallow depth of field",
            "slow pan", "dolly in", "dolly out", "tracking shot", "handheld", "steadicam", "static tripod",
            "crane shot", "drone aerial", "orbit shot", "whip pan", "low angle", "high angle"
        ]
        let lower = text.lowercased()
        return candidates.filter { lower.contains($0) }.joined(separator: ", ")
    }

    private func inferLightingCues(from text: String) -> String {
        let candidates = [
            "golden hour", "blue hour", "neon lighting", "rim light", "volumetric fog", "softbox",
            "chiaroscuro", "overcast daylight", "harsh noon sun", "candlelight", "backlit", "bioluminescent",
            "studio key light", "moonlight", "dramatic shadows"
        ]
        let lower = text.lowercased()
        return candidates.filter { lower.contains($0) }.joined(separator: ", ")
    }

    private func detectSeparateOutputsRequest(in text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("separate image") ||
            lower.contains("separate portrait") ||
            lower.contains("individual image") ||
            lower.contains("not a collage") ||
            lower.contains("one per image") ||
            lower.contains("distinct images")
    }

    private func inferTechnicalParameters(from text: String, beats: [VideoBeat]) -> TechnicalParameterSet {
        var params = TechnicalParameterSet()
        let lower = text.lowercased()

        // Aspect ratio
        if let arMatch = text.range(of: #"\b(1:1|16:9|9:16|4:3|3:4|3:2|2:3|21:9|1:4|4:1|1:8|8:1|4:5|5:4)\b"#, options: .regularExpression) {
            params.aspectRatio = String(text[arMatch])
        }

        // Dimensions (1024x1024, 1920x1080)
        if let dimRegex = try? NSRegularExpression(pattern: #"\b(\d{3,4})\s*[x×]\s*(\d{3,4})\b"#, options: [.caseInsensitive]),
           let match = dimRegex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
            let nsText = text as NSString
            params.width = Int(nsText.substring(with: match.range(at: 1)))
            params.height = Int(nsText.substring(with: match.range(at: 2)))
        }

        // Resolution tier
        if lower.contains("4k") { params.resolutionTier = "4K" }
        else if lower.contains("2k") { params.resolutionTier = "2K" }
        else if lower.contains("1080p") { params.resolutionTier = "1080p" }
        else if lower.contains("720p") { params.resolutionTier = "720p" }
        else if lower.contains("480p") { params.resolutionTier = "480p" }
        else if lower.contains("1k") { params.resolutionTier = "1K" }

        // Duration
        if let durRegex = try? NSRegularExpression(pattern: #"(?i)\b(\d+(?:\.\d+)?)\s*(?:seconds?|secs?|s)\b"#),
           let match = durRegex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
            let nsText = text as NSString
            params.durationSeconds = Double(nsText.substring(with: match.range(at: 1)))
        } else if let maxBeatEnd = beats.compactMap(\.endSeconds).max() {
            params.durationSeconds = maxBeatEnd
        }

        // Transparent background cue
        if lower.contains("transparent background") || lower.contains("alpha channel") {
            params.backgroundMode = "transparent"
        }

        // Separate image batch count
        if detectSeparateOutputsRequest(in: text) {
            if let numRegex = try? NSRegularExpression(pattern: #"(?i)\b(\d+)\s+separate\b"#),
               let match = numRegex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
                params.batchCount = Int((text as NSString).substring(with: match.range(at: 1)))
            }
        }

        return params
    }

    private func mergeParameters(inferred: TechnicalParameterSet, overrides: TechnicalParameterSet) -> TechnicalParameterSet {
        TechnicalParameterSet(
            aspectRatio: overrides.aspectRatio ?? inferred.aspectRatio,
            width: overrides.width ?? inferred.width,
            height: overrides.height ?? inferred.height,
            resolutionTier: overrides.resolutionTier ?? inferred.resolutionTier,
            durationSeconds: overrides.durationSeconds ?? inferred.durationSeconds,
            batchCount: overrides.batchCount ?? inferred.batchCount,
            steps: overrides.steps ?? inferred.steps,
            cfgScale: overrides.cfgScale ?? inferred.cfgScale,
            seed: overrides.seed ?? inferred.seed,
            sampler: overrides.sampler ?? inferred.sampler,
            qualityTier: overrides.qualityTier ?? inferred.qualityTier,
            backgroundMode: overrides.backgroundMode ?? inferred.backgroundMode,
            outputFormat: overrides.outputFormat ?? inferred.outputFormat,
            inputFidelity: overrides.inputFidelity ?? inferred.inputFidelity,
            reasoningEffort: overrides.reasoningEffort ?? inferred.reasoningEffort,
            thinkingLevel: overrides.thinkingLevel ?? inferred.thinkingLevel,
            jsonSchemaHint: overrides.jsonSchemaHint ?? inferred.jsonSchemaHint
        )
    }

    private func buildInvariants(
        lexResult: PromptLexResult,
        ingredients: PromptIngredients,
        manualLocks: [String]
    ) -> [SemanticInvariant] {
        var invariants: [SemanticInvariant] = []
        var seenTokens = Set<String>()

        for span in lexResult.spans {
            let token: String
            let kind: InvariantKind
            let label: String

            switch span.kind {
            case .codeFence, .inlineCode, .templateVariable, .wildcard, .loraOrLyco, .embedding, .qualityScoreTag, .videoReference, .audioStructureTag, .url, .filePath:
                token = span.text
                kind = .preserveProtectedSpan
                label = "Preserve \(span.kind.displayLabel): \(span.text)"
            case .quotedLiteral:
                token = span.normalizedPayload
                kind = .preserveTextLiteral
                label = "Preserve exact literal: \"\(span.normalizedPayload)\""
            case .explicitLock:
                token = span.normalizedPayload
                kind = .preserveProtectedSpan
                label = "Explicit Lock: \(span.normalizedPayload)"
            case .negativeDirective:
                token = span.normalizedPayload
                kind = .preserveExclusion
                label = "Preserve exclusion: \(span.normalizedPayload)"
            case .timestampCue, .numericConstraint:
                continue
            }

            let key = "\(kind.rawValue)|\(token.lowercased())"
            if seenTokens.insert(key).inserted {
                invariants.append(SemanticInvariant(kind: kind, label: label, requiredToken: token))
            }
        }

        for countReq in lexResult.subjectCounts {
            let token = "\(countReq.rawCountToken) \(countReq.entity)"
            let key = "\(InvariantKind.preserveSubjectCount.rawValue)|\(countReq.count)|\(countReq.entity.lowercased())"
            if seenTokens.insert(key).inserted {
                invariants.append(
                    SemanticInvariant(
                        kind: .preserveSubjectCount,
                        label: "Preserve exact count: \(token)",
                        requiredToken: token
                    )
                )
            }
        }

        for exclusion in ingredients.negativeIntent {
            let key = "\(InvariantKind.preserveExclusion.rawValue)|\(exclusion.lowercased())"
            if seenTokens.insert(key).inserted {
                invariants.append(
                    SemanticInvariant(
                        kind: .preserveExclusion,
                        label: "Preserve exclusion: \(exclusion)",
                        requiredToken: exclusion
                    )
                )
            }
        }

        if ingredients.separateOutputsRequested {
            invariants.append(
                SemanticInvariant(
                    kind: .forbidCollageMerge,
                    label: "Separate outputs requested (forbid collage/grid merge)",
                    requiredToken: "separate"
                )
            )
        }

        for ref in ingredients.referenceAssets {
            let key = "\(InvariantKind.preserveReferenceBinding.rawValue)|\(ref.label.lowercased())"
            if seenTokens.insert(key).inserted {
                invariants.append(
                    SemanticInvariant(
                        kind: .preserveReferenceBinding,
                        label: "Bind reference asset [\(ref.role.displayName)]: \(ref.label)",
                        requiredToken: ref.label
                    )
                )
            }
        }

        for manual in manualLocks where !manual.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let clean = manual.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = "\(InvariantKind.preserveProtectedSpan.rawValue)|\(clean.lowercased())"
            if seenTokens.insert(key).inserted {
                invariants.append(
                    SemanticInvariant(
                        kind: .preserveProtectedSpan,
                        label: "User Lock: \(clean)",
                        requiredToken: clean
                    )
                )
            }
        }

        return invariants
    }

    private func containsAny(_ text: String, cues: [String]) -> Bool {
        cues.contains { text.contains($0) }
    }

    private func appendUnique(_ value: String, to array: inout [String]) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !array.contains(trimmed) else { return }
        array.append(trimmed)
    }
}
