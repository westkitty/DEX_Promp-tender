import Foundation

enum ProviderGatewayError: LocalizedError {
    case explicitConfirmationRequired
    case blockingProofIssues
    case missingAPIKey(APIKeyProvider)
    case unsupportedDestination(TargetDestination)
    case httpError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .explicitConfirmationRequired:
            return "External provider requests require explicit Serve confirmation."
        case .blockingProofIssues:
            return "Resolve blocking Proof issues before sending an external API request."
        case .missingAPIKey(let provider):
            return "No \(provider.displayName) API key saved in macOS Keychain."
        case .unsupportedDestination(let target):
            return "\(target.displayName) does not map to a cloud API adapter."
        case .httpError(let code, let message):
            return "Provider HTTP \(code): \(message)"
        }
    }
}

struct ProviderSubmissionReceipt: Equatable {
    let provider: APIKeyProvider
    let endpointURL: String
    let statusCode: Int
    let responseBody: String
}

/// Strictly opt-in HTTP gateway for xAI, OpenAI, and Google Gemini APIs.
/// Requires an explicit `ServeAuthorizationToken`, zero blocking proof checks, and a Keychain-stored API key.
final class ProviderAPIRouter {
    private let secretStore: SecretStoreProtocol
    private let transport: HTTPTransportProtocol

    init(
        secretStore: SecretStoreProtocol = KeychainSecretStore(),
        transport: HTTPTransportProtocol = URLSessionHTTPTransport(timeoutSeconds: 30.0)
    ) {
        self.secretStore = secretStore
        self.transport = transport
    }

    static func providerKey(for destination: TargetDestination) -> APIKeyProvider? {
        switch destination {
        case .grokImagineImage, .grokImagineVideo:
            return .xai
        case .openAIImage, .openAITextAgent:
            return .openAI
        case .geminiImage, .geminiVideo, .geminiTextAgent:
            return .gemini
        default:
            return nil
        }
    }

    static func endpointURL(for result: CompilationResult) -> URL? {
        switch result.target {
        case .grokImagineImage:
            let ep = result.recommendedParameters["endpoint"] == "/v1/images/edits" ? "v1/images/edits" : "v1/images/generations"
            return URL(string: "https://api.x.ai/\(ep)")
        case .grokImagineVideo:
            return URL(string: "https://api.x.ai/v1/videos/generations")
        case .openAIImage:
            let ep = result.recommendedParameters["endpoint"] == "/v1/images/edits" ? "v1/images/edits" : "v1/images/generations"
            return URL(string: "https://api.openai.com/\(ep)")
        case .openAITextAgent:
            return URL(string: "https://api.openai.com/v1/responses")
        case .geminiImage, .geminiTextAgent:
            return URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(result.modelID):generateContent")
        case .geminiVideo:
            let action = result.modelID.contains("veo") ? "predictLongRunning" : "generateContent"
            return URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(result.modelID):\(action)")
        default:
            return nil
        }
    }

    func readiness(for destination: TargetDestination) -> ReadinessState {
        guard let provider = Self.providerKey(for: destination) else {
            return .sourceImplemented
        }
        return secretStore.hasSecret(for: provider)
            ? .availableToUser
            : .blocked(reason: "API key not configured in Keychain (prompt-only offline ready)")
    }

    func buildRedactedRequestPreview(for result: CompilationResult) throws -> (url: String, headers: [String: String], body: String) {
        guard let provider = Self.providerKey(for: result.target),
              let url = Self.endpointURL(for: result) else {
            throw ProviderGatewayError.unsupportedDestination(result.target)
        }
        var headers: [String: String] = ["Content-Type": "application/json"]
        switch provider {
        case .xai, .openAI:
            headers["Authorization"] = "Bearer [REDACTED_KEYCHAIN_\(provider.rawValue.uppercased())]"
        case .gemini:
            headers["x-goog-api-key"] = "[REDACTED_KEYCHAIN_GEMINI_API_KEY]"
        }
        return (url.absoluteString, headers, result.structuredPayloadJSON)
    }

    func submit(
        result: CompilationResult,
        authorization: ServeAuthorizationToken
    ) async throws -> ProviderSubmissionReceipt {
        guard authorization.channel == .submitAuthorizedProviderAPI else {
            throw ProviderGatewayError.explicitConfirmationRequired
        }
        guard !result.proofReport.hasBlockingIssues else {
            throw ProviderGatewayError.blockingProofIssues
        }
        guard let provider = Self.providerKey(for: result.target),
              let url = Self.endpointURL(for: result) else {
            throw ProviderGatewayError.unsupportedDestination(result.target)
        }
        guard let apiKey = try secretStore.loadSecret(for: provider), !apiKey.isEmpty else {
            throw ProviderGatewayError.missingAPIKey(provider)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch provider {
        case .xai, .openAI:
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .gemini:
            req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        }
        req.httpBody = result.structuredPayloadJSON.data(using: .utf8)

        let (data, http) = try await transport.send(req)
        let bodyText = String(decoding: data, as: UTF8.self)
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderGatewayError.httpError(statusCode: http.statusCode, message: bodyText)
        }
        return ProviderSubmissionReceipt(
            provider: provider,
            endpointURL: url.absoluteString,
            statusCode: http.statusCode,
            responseBody: bodyText
        )
    }
}
