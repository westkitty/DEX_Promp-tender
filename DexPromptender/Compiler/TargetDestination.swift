import Foundation

/// Explicit 8-state runtime readiness taxonomy distinguished strictly by evidence level.
enum ReadinessState: Equatable, Codable, Hashable {
    case sourceImplemented
    case runtimeReachable
    case capabilityAdvertised
    case capabilityProven
    case availableToUser
    case currentlyReady
    case unknown
    case blocked(reason: String)

    var badgeLabel: String {
        switch self {
        case .sourceImplemented: return "Source Implemented"
        case .runtimeReachable: return "Runtime Reachable"
        case .capabilityAdvertised: return "Capability Advertised"
        case .capabilityProven: return "Capability Proven"
        case .availableToUser: return "Available"
        case .currentlyReady: return "Ready"
        case .unknown: return "Unknown"
        case .blocked(let reason): return reason.isEmpty ? "Blocked" : "Blocked: \(reason)"
        }
    }

    var isLiveSubmittable: Bool {
        switch self {
        case .capabilityProven, .availableToUser, .currentlyReady:
            return true
        default:
            return false
        }
    }
}

enum MixMode: String, Codable, CaseIterable, Identifiable {
    case neat = "neat"
    case stirred = "stirred"
    case shaken = "shaken"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .neat: return "Neat"
        case .stirred: return "Stirred"
        case .shaken: return "Shaken"
        }
    }

    var plainDescription: String {
        switch self {
        case .neat: return "Conservative cleanup, minimal rewrite"
        case .stirred: return "Balanced restructuring for the target"
        case .shaken: return "Creative expansion with explicit locks"
        }
    }
}

/// All 8 required model-family destinations plus legacy DexCraft text destinations.
enum TargetDestination: String, Codable, CaseIterable, Identifiable {
    case dexDiffusionImage = "dex_diffusion_image"
    case grokImagineImage = "grok_imagine_image"
    case grokImagineVideo = "grok_imagine_video"
    case openAIImage = "openai_gpt_image"
    case openAITextAgent = "openai_gpt_text_agent"
    case geminiImage = "gemini_image"
    case geminiVideo = "gemini_video"
    case geminiTextAgent = "gemini_text_agent"
    // Preserved upstream DexCraft targets (first-class alongside the 8 model families)
    case claudeTextAgent = "claude_text_agent"
    case perplexityResearch = "perplexity_research"
    case agenticIDEWorkflow = "agentic_ide_workflow"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dexDiffusionImage: return "DexDiffusion (Image)"
        case .grokImagineImage: return "Grok Imagine (Image)"
        case .grokImagineVideo: return "Grok Imagine (Video)"
        case .openAIImage: return "OpenAI GPT Image"
        case .openAITextAgent: return "OpenAI GPT Text / Agent"
        case .geminiImage: return "Gemini Image (Nano Banana)"
        case .geminiVideo: return "Gemini Video (Omni / Veo)"
        case .geminiTextAgent: return "Gemini Text / Agent"
        case .claudeTextAgent: return "Claude XML Text / Agent"
        case .perplexityResearch: return "Perplexity Research"
        case .agenticIDEWorkflow: return "Agentic IDE Workflow"
        }
    }

    var shortName: String {
        switch self {
        case .dexDiffusionImage: return "DexDiffusion"
        case .grokImagineImage: return "Grok Img"
        case .grokImagineVideo: return "Grok Vid"
        case .openAIImage: return "GPT Img"
        case .openAITextAgent: return "GPT Text"
        case .geminiImage: return "Gemini Img"
        case .geminiVideo: return "Gemini Vid"
        case .geminiTextAgent: return "Gemini Text"
        case .claudeTextAgent: return "Claude"
        case .perplexityResearch: return "Perplexity"
        case .agenticIDEWorkflow: return "Agentic IDE"
        }
    }

    var isImageTarget: Bool {
        switch self {
        case .dexDiffusionImage, .grokImagineImage, .openAIImage, .geminiImage:
            return true
        default:
            return false
        }
    }

    var isVideoTarget: Bool {
        self == .grokImagineVideo || self == .geminiVideo
    }

    var isTextOrAgentTarget: Bool {
        !isImageTarget && !isVideoTarget
    }

    /// Maps preserved legacy DexCraft `PromptTarget` values cleanly.
    init(legacyTarget: PromptTarget) {
        switch legacyTarget {
        case .claude: self = .claudeTextAgent
        case .geminiChatGPT: self = .openAITextAgent
        case .perplexity: self = .perplexityResearch
        case .agenticIDE: self = .agenticIDEWorkflow
        }
    }

    var legacyPromptTarget: PromptTarget {
        switch self {
        case .claudeTextAgent: return .claude
        case .perplexityResearch: return .perplexity
        case .agenticIDEWorkflow: return .agenticIDE
        default: return .geminiChatGPT
        }
    }
}

enum ProvenanceSource: String, Codable, CaseIterable {
    case userAuthored = "user_authored"
    case deterministicParser = "deterministic_parser"
    case providerProfile = "provider_profile"
    case heuristicTransform = "heuristic_transform"
    case embeddedTinyLLM = "embedded_tiny_llm"
    case authorizedRemoteLLM = "authorized_remote_llm"

    var badgeLabel: String {
        switch self {
        case .userAuthored: return "User Input"
        case .deterministicParser: return "Parser"
        case .providerProfile: return "Target Recipe"
        case .heuristicTransform: return "Heuristic"
        case .embeddedTinyLLM: return "Local Tiny LLM"
        case .authorizedRemoteLLM: return "Remote AI"
        }
    }
}

struct ProvenanceEntry: Identifiable, Equatable, Codable {
    let id: UUID
    let source: ProvenanceSource
    let section: String
    let note: String

    init(id: UUID = UUID(), source: ProvenanceSource, section: String, note: String) {
        self.id = id
        self.source = source
        self.section = section
        self.note = note
    }
}

enum ProofSeverity: String, Codable, Comparable {
    case pass = "pass"
    case warning = "warning"
    case blocking = "blocking"

    static func < (lhs: ProofSeverity, rhs: ProofSeverity) -> Bool {
        let rank: [ProofSeverity: Int] = [.pass: 0, .warning: 1, .blocking: 2]
        return (rank[lhs] ?? 0) < (rank[rhs] ?? 0)
    }
}

struct ProofItem: Identifiable, Equatable, Codable {
    let id: UUID
    let severity: ProofSeverity
    let category: String
    let title: String
    let detail: String
    let remediation: String?

    init(
        id: UUID = UUID(),
        severity: ProofSeverity,
        category: String,
        title: String,
        detail: String,
        remediation: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.category = category
        self.title = title
        self.detail = detail
        self.remediation = remediation
    }
}

struct ProofReport: Equatable, Codable {
    let items: [ProofItem]
    let characterCount: Int
    let characterLimit: Int?

    var passCount: Int { items.filter { $0.severity == .pass }.count }
    var warningCount: Int { items.filter { $0.severity == .warning }.count }
    var blockingCount: Int { items.filter { $0.severity == .blocking }.count }

    var hasBlockingIssues: Bool { blockingCount > 0 }

    var summaryBadge: String {
        if blockingCount > 0 {
            return "\(blockingCount) Blocking"
        } else if warningCount > 0 {
            return "\(warningCount) Warning\(warningCount == 1 ? "" : "s")"
        } else {
            return "Proof Passed (\(passCount))"
        }
    }
}

enum ServeChannel: String, Codable, CaseIterable, Identifiable {
    case copyPrompt = "copy_prompt"
    case copyPayloadJSON = "copy_payload_json"
    case exportArtifact = "export_artifact"
    case openDexDiffusionStudio = "open_dexdiffusion_studio"
    case submitDexDiffusionControlled = "submit_dexdiffusion_controlled"
    case submitAuthorizedProviderAPI = "submit_authorized_provider_api"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .copyPrompt: return "Copy Compiled Prompt"
        case .copyPayloadJSON: return "Copy Target JSON Payload"
        case .exportArtifact: return "Export File"
        case .openDexDiffusionStudio: return "Open in DexDiffusion Studio"
        case .submitDexDiffusionControlled: return "Submit to DexDiffusion Worker"
        case .submitAuthorizedProviderAPI: return "Submit to Provider API"
        }
    }

    var isExternalSubmission: Bool {
        self == .submitDexDiffusionControlled || self == .submitAuthorizedProviderAPI
    }
}

struct CompilationResult: Identifiable, Equatable {
    let id: UUID
    let target: TargetDestination
    let modelID: String
    let recipeVersion: String
    let mixMode: MixMode
    let compiledPrompt: String
    let negativePrompt: String?
    let systemInstructions: String?
    let structuredPayloadJSON: String
    let recommendedParameters: [String: String]
    let provenance: [ProvenanceEntry]
    let proofReport: ProofReport
    let semanticDiff: SemanticDiffReport
    let readiness: ReadinessState
    let compilationDurationMs: Int
}
