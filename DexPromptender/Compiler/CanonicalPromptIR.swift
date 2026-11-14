import Foundation

enum IntentKind: String, Codable, CaseIterable {
    case imageGeneration = "image_generation"
    case imageEdit = "image_edit"
    case videoGeneration = "video_generation"
    case codingAgent = "coding_agent"
    case researchAnalysis = "research_analysis"
    case structuredOutput = "structured_output"
    case generalText = "general_text"

    var displayName: String {
        switch self {
        case .imageGeneration: return "Image Generation"
        case .imageEdit: return "Image Editing"
        case .videoGeneration: return "Video Generation"
        case .codingAgent: return "Coding / Agentic"
        case .researchAnalysis: return "Research / Analysis"
        case .structuredOutput: return "Structured Output"
        case .generalText: return "General Text"
        }
    }
}

enum ReferenceAssetRole: String, Codable, CaseIterable, Identifiable {
    case subject = "subject"
    case style = "style"
    case character = "character"
    case object = "object"
    case voice = "voice"
    case mask = "mask"
    case editSource = "edit_source"
    case startFrame = "start_frame"
    case endFrame = "end_frame"
    case videoClip = "video_clip"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .subject: return "Subject"
        case .style: return "Style"
        case .character: return "Character"
        case .object: return "Object"
        case .voice: return "Voice Ref"
        case .mask: return "Edit Mask"
        case .editSource: return "Edit Source"
        case .startFrame: return "Start Frame"
        case .endFrame: return "End Frame"
        case .videoClip: return "Video Clip"
        }
    }
}

struct ReferenceAsset: Identifiable, Codable, Hashable {
    var id: UUID
    var label: String
    var pathOrURI: String
    var role: ReferenceAssetRole
    var notes: String

    init(
        id: UUID = UUID(),
        label: String,
        pathOrURI: String,
        role: ReferenceAssetRole,
        notes: String = ""
    ) {
        self.id = id
        self.label = label
        self.pathOrURI = pathOrURI
        self.role = role
        self.notes = notes
    }
}

struct AudioCueSpec: Equatable, Codable {
    var spokenDialogue: [String]
    var soundEffects: [String]
    var ambientAudio: String
    var requiresLipSync: Bool
    var suppressAudio: Bool

    init(
        spokenDialogue: [String] = [],
        soundEffects: [String] = [],
        ambientAudio: String = "",
        requiresLipSync: Bool = false,
        suppressAudio: Bool = false
    ) {
        self.spokenDialogue = spokenDialogue
        self.soundEffects = soundEffects
        self.ambientAudio = ambientAudio
        self.requiresLipSync = requiresLipSync
        self.suppressAudio = suppressAudio
    }

    var isEmpty: Bool {
        spokenDialogue.isEmpty && soundEffects.isEmpty && ambientAudio.isEmpty && !requiresLipSync && !suppressAudio
    }
}

struct VideoBeat: Identifiable, Equatable, Codable {
    var id: UUID
    var index: Int
    var timecodeLabel: String
    var startSeconds: Double?
    var endSeconds: Double?
    var visualAction: String
    var cameraMotion: String
    var startState: String
    var endState: String
    var transitionToNext: String
    var audioCue: String

    init(
        id: UUID = UUID(),
        index: Int,
        timecodeLabel: String,
        startSeconds: Double? = nil,
        endSeconds: Double? = nil,
        visualAction: String,
        cameraMotion: String = "",
        startState: String = "",
        endState: String = "",
        transitionToNext: String = "",
        audioCue: String = ""
    ) {
        self.id = id
        self.index = index
        self.timecodeLabel = timecodeLabel
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.visualAction = visualAction
        self.cameraMotion = cameraMotion
        self.startState = startState
        self.endState = endState
        self.transitionToNext = transitionToNext
        self.audioCue = audioCue
    }
}

struct TechnicalParameterSet: Equatable, Codable {
    var aspectRatio: String?
    var width: Int?
    var height: Int?
    var resolutionTier: String?       // e.g. "1K", "2K", "4K", "480p", "720p", "1080p"
    var durationSeconds: Double?
    var batchCount: Int?              // e.g. n=1..10 or separate images count
    var steps: Int?
    var cfgScale: Double?
    var seed: Int?
    var sampler: String?
    var qualityTier: String?          // e.g. "low", "medium", "high", "xhigh", "max"
    var backgroundMode: String?       // e.g. "auto", "transparent", "opaque"
    var outputFormat: String?         // e.g. "png", "webp", "jpeg", "json"
    var inputFidelity: String?        // e.g. "low", "high"
    var reasoningEffort: String?      // e.g. "low", "medium", "high"
    var thinkingLevel: String?        // e.g. "minimal", "medium", "high"
    var jsonSchemaHint: String?

    init(
        aspectRatio: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        resolutionTier: String? = nil,
        durationSeconds: Double? = nil,
        batchCount: Int? = nil,
        steps: Int? = nil,
        cfgScale: Double? = nil,
        seed: Int? = nil,
        sampler: String? = nil,
        qualityTier: String? = nil,
        backgroundMode: String? = nil,
        outputFormat: String? = nil,
        inputFidelity: String? = nil,
        reasoningEffort: String? = nil,
        thinkingLevel: String? = nil,
        jsonSchemaHint: String? = nil
    ) {
        self.aspectRatio = aspectRatio
        self.width = width
        self.height = height
        self.resolutionTier = resolutionTier
        self.durationSeconds = durationSeconds
        self.batchCount = batchCount
        self.steps = steps
        self.cfgScale = cfgScale
        self.seed = seed
        self.sampler = sampler
        self.qualityTier = qualityTier
        self.backgroundMode = backgroundMode
        self.outputFormat = outputFormat
        self.inputFidelity = inputFidelity
        self.reasoningEffort = reasoningEffort
        self.thinkingLevel = thinkingLevel
        self.jsonSchemaHint = jsonSchemaHint
    }
}

struct PromptIngredients: Equatable, Codable {
    var subject: String
    var action: String
    var sceneContext: String
    var spatialRelations: [String]
    var styleMedium: String
    var cameraComposition: String
    var lightingAtmosphere: String
    var audioDialogue: AudioCueSpec
    var temporalTimeline: [VideoBeat]
    var continuityAnchors: [String]
    var referenceAssets: [ReferenceAsset]
    var constraints: [String]
    var negativeIntent: [String]
    var deliverables: [String]
    var outputContract: [String]
    var separateOutputsRequested: Bool
    var technicalParams: TechnicalParameterSet

    init(
        subject: String = "",
        action: String = "",
        sceneContext: String = "",
        spatialRelations: [String] = [],
        styleMedium: String = "",
        cameraComposition: String = "",
        lightingAtmosphere: String = "",
        audioDialogue: AudioCueSpec = AudioCueSpec(),
        temporalTimeline: [VideoBeat] = [],
        continuityAnchors: [String] = [],
        referenceAssets: [ReferenceAsset] = [],
        constraints: [String] = [],
        negativeIntent: [String] = [],
        deliverables: [String] = [],
        outputContract: [String] = [],
        separateOutputsRequested: Bool = false,
        technicalParams: TechnicalParameterSet = TechnicalParameterSet()
    ) {
        self.subject = subject
        self.action = action
        self.sceneContext = sceneContext
        self.spatialRelations = spatialRelations
        self.styleMedium = styleMedium
        self.cameraComposition = cameraComposition
        self.lightingAtmosphere = lightingAtmosphere
        self.audioDialogue = audioDialogue
        self.temporalTimeline = temporalTimeline
        self.continuityAnchors = continuityAnchors
        self.referenceAssets = referenceAssets
        self.constraints = constraints
        self.negativeIntent = negativeIntent
        self.deliverables = deliverables
        self.outputContract = outputContract
        self.separateOutputsRequested = separateOutputsRequested
        self.technicalParams = technicalParams
    }
}

enum InvariantKind: String, Codable, Hashable {
    case preserveProtectedSpan = "preserve_protected_span"
    case preserveSubjectCount = "preserve_subject_count"
    case preserveExclusion = "preserve_exclusion"
    case forbidCollageMerge = "forbid_collage_merge"
    case preserveTextLiteral = "preserve_text_literal"
    case preserveReferenceBinding = "preserve_reference_binding"
}

struct SemanticInvariant: Identifiable, Hashable, Codable {
    let id: UUID
    let kind: InvariantKind
    let label: String
    let requiredToken: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        kind: InvariantKind,
        label: String,
        requiredToken: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.requiredToken = requiredToken
        self.isEnabled = isEnabled
    }
}

struct CanonicalPromptIR: Equatable, Codable {
    let id: UUID
    let createdAt: Date
    let rawInput: String
    let lexResult: PromptLexResult
    var intentKind: IntentKind
    var ingredients: PromptIngredients
    var invariants: [SemanticInvariant]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        rawInput: String,
        lexResult: PromptLexResult,
        intentKind: IntentKind,
        ingredients: PromptIngredients,
        invariants: [SemanticInvariant]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rawInput = rawInput
        self.lexResult = lexResult
        self.intentKind = intentKind
        self.ingredients = ingredients
        self.invariants = invariants
    }
}
