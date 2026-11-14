import Foundation

enum ProtectedSpanKind: String, Codable, CaseIterable, Hashable {
    case codeFence = "code_fence"
    case inlineCode = "inline_code"
    case templateVariable = "template_variable"
    case wildcard = "wildcard"
    case loraOrLyco = "lora_or_lyco"
    case embedding = "embedding"
    case qualityScoreTag = "quality_score_tag"
    case videoReference = "video_reference"
    case audioStructureTag = "audio_structure_tag"
    case timestampCue = "timestamp_cue"
    case quotedLiteral = "quoted_literal"
    case url = "url"
    case filePath = "file_path"
    case explicitLock = "explicit_lock"
    case negativeDirective = "negative_directive"
    case numericConstraint = "numeric_constraint"

    var displayLabel: String {
        switch self {
        case .codeFence: return "Code Block"
        case .inlineCode: return "Inline Code"
        case .templateVariable: return "Variable"
        case .wildcard: return "Wildcard"
        case .loraOrLyco: return "LoRA Tag"
        case .embedding: return "Embedding"
        case .qualityScoreTag: return "Model Tag"
        case .videoReference: return "Video/Media Ref"
        case .audioStructureTag: return "Audio/Section Cue"
        case .timestampCue: return "Timeline Cue"
        case .quotedLiteral: return "Quoted Literal"
        case .url: return "URL"
        case .filePath: return "File Path"
        case .explicitLock: return "Explicit Lock"
        case .negativeDirective: return "Negative Directive"
        case .numericConstraint: return "Quantity/Dimension"
        }
    }

    /// Indicates whether a diffusion positive prompt may relocate this token (e.g. negative directive -> negative_prompt)
    /// rather than strictly keeping it inside the positive body verbatim.
    var canRelocateToTargetSlot: Bool {
        switch self {
        case .negativeDirective:
            return true
        case .numericConstraint:
            return true
        default:
            return false
        }
    }
}

struct ProtectedSpan: Identifiable, Hashable, Codable {
    let id: UUID
    let kind: ProtectedSpanKind
    let text: String
    /// Payload stripped of marker syntax when applicable (e.g., content inside lock:... or NOT:...).
    let normalizedPayload: String
    let utf16Location: Int
    let utf16Length: Int
    let lineNumber: Int

    init(
        id: UUID = UUID(),
        kind: ProtectedSpanKind,
        text: String,
        normalizedPayload: String? = nil,
        utf16Location: Int,
        utf16Length: Int,
        lineNumber: Int
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.normalizedPayload = normalizedPayload ?? text
        self.utf16Location = utf16Location
        self.utf16Length = utf16Length
        self.lineNumber = lineNumber
    }

    var nsRange: NSRange {
        NSRange(location: utf16Location, length: utf16Length)
    }
}

struct SubjectCountRequirement: Identifiable, Hashable, Codable {
    let id: UUID
    let count: Int
    let rawCountToken: String
    let entity: String

    init(id: UUID = UUID(), count: Int, rawCountToken: String, entity: String) {
        self.id = id
        self.count = count
        self.rawCountToken = rawCountToken
        self.entity = entity
    }
}

struct PromptLexResult: Equatable, Codable {
    let rawInput: String
    let spans: [ProtectedSpan]
    let variables: [String]
    let wildcards: [String]
    let loras: [String]
    let videoRefs: [String]
    let quotedLiterals: [String]
    let subjectCounts: [SubjectCountRequirement]

    func spans(of kind: ProtectedSpanKind) -> [ProtectedSpan] {
        spans.filter { $0.kind == kind }
    }
}
