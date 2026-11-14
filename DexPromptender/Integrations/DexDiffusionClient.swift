import Foundation

protocol HTTPTransportProtocol {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class URLSessionHTTPTransport: HTTPTransportProtocol {
    private let session: URLSession

    init(timeoutSeconds: TimeInterval = 3.0) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutSeconds
        config.timeoutIntervalForResource = max(timeoutSeconds, 6.0)
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

struct DexDiffusionVersionInfo: Equatable, Codable {
    let name: String
    let version: String
    let gitHead: String
    let pid: Int?
    let storageMode: String?
    let canonicalImages: String?
}

struct DexDiffusionTargetCapability: Identifiable, Equatable {
    let id: String
    let family: String
    let engine: String
    let status: String
    let proofState: String
    let reason: String?

    var readinessState: ReadinessState {
        let st = status.lowercased()
        let pr = proofState.lowercased()
        if st == "available" && pr == "proofed" {
            return .capabilityProven
        }
        if st == "available" {
            return .capabilityAdvertised
        }
        if let reason, !reason.isEmpty {
            return .blocked(reason: reason)
        }
        return .blocked(reason: status)
    }
}

struct DexDiffusionCapabilitiesSnapshot: Equatable {
    let fetchedAt: Date
    let configurationDegraded: Bool
    let editWorkerTarget: String?
    let targets: [DexDiffusionTargetCapability]
    let reachable: Bool
    let diagnosticSummary: String
}

struct DexDiffusionWildcardBank: Identifiable, Equatable {
    let id: String
    let name: String
    let count: Int
    let sampleEntries: [String]
}

struct ServeAuthorizationToken {
    let channel: ServeChannel
    let approvedAt: Date
    let targetID: String

    init(channel: ServeChannel, targetID: String, approvedAt: Date = Date()) {
        self.channel = channel
        self.targetID = targetID
        self.approvedAt = approvedAt
    }
}

enum DexDiffusionClientError: LocalizedError {
    case unauthorizedSubmission
    case blockingProofIssues
    case serverError(statusCode: Int, message: String)
    case invalidEndpoint

    var errorDescription: String? {
        switch self {
        case .unauthorizedSubmission:
            return "DexDiffusion generation requires explicit user Serve confirmation."
        case .blockingProofIssues:
            return "Resolve blocking Strain & Proof issues before submitting to DexDiffusion."
        case .serverError(let code, let msg):
            return "DexDiffusion HTTP \(code): \(msg)"
        case .invalidEndpoint:
            return "Invalid DexDiffusion base URL."
        }
    }
}

/// Capability-aware read/preview/controlled-submit client for local DexDiffusion (`127.0.0.1:31337`).
/// Never duplicates generation workers or canonical storage.
final class DexDiffusionClient {
    let baseURL: URL
    private let transport: HTTPTransportProtocol

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:31337")!,
        transport: HTTPTransportProtocol = URLSessionHTTPTransport(timeoutSeconds: 2.5)
    ) {
        self.baseURL = baseURL
        self.transport = transport
    }

    var studioURL: URL {
        baseURL.appendingPathComponent("dexdiffusion/")
    }

    func fetchVersion() async throws -> DexDiffusionVersionInfo {
        let req = URLRequest(url: baseURL.appendingPathComponent("api/version"))
        let (data, http) = try await transport.send(req)
        guard (200..<300).contains(http.statusCode) else {
            throw DexDiffusionClientError.serverError(statusCode: http.statusCode, message: String(decoding: data, as: UTF8.self))
        }
        let raw = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let storage = raw["storage"] as? [String: Any]
        return DexDiffusionVersionInfo(
            name: (raw["name"] as? String) ?? "DexDiffusion",
            version: (raw["version"] as? String) ?? "unknown",
            gitHead: (raw["gitHead"] as? String) ?? "unknown",
            pid: raw["pid"] as? Int,
            storageMode: storage?["mode"] as? String,
            canonicalImages: storage?["canonicalImages"] as? String
        )
    }

    func fetchCapabilities() async -> DexDiffusionCapabilitiesSnapshot {
        let url = baseURL.appendingPathComponent("api/capabilities")
        do {
            let (data, http) = try await transport.send(URLRequest(url: url))
            guard (200..<300).contains(http.statusCode),
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return DexDiffusionCapabilitiesSnapshot(
                    fetchedAt: Date(),
                    configurationDegraded: true,
                    editWorkerTarget: nil,
                    targets: [],
                    reachable: false,
                    diagnosticSummary: "DexDiffusion returned HTTP \(http.statusCode)."
                )
            }

            let config = root["configuration"] as? [String: Any]
            let degraded = (config?["degraded"] as? Bool) ?? false
            let editTarget = root["editWorkerTarget"] as? String
            var parsedTargets: [DexDiffusionTargetCapability] = []

            if let targetMap = root["modelTargets"] as? [String: Any] {
                for (id, value) in targetMap.sorted(by: { $0.key < $1.key }) {
                    guard let entry = value as? [String: Any] else { continue }
                    let cap = DexDiffusionTargetCapability(
                        id: id,
                        family: (entry["family"] as? String) ?? "diffusion",
                        engine: (entry["engine"] as? String) ?? "unknown",
                        status: (entry["status"] as? String) ?? "unknown",
                        proofState: (entry["proofState"] as? String) ?? (entry["proof"] as? String) ?? "unproven",
                        reason: entry["reason"] as? String
                    )
                    parsedTargets.append(cap)
                }
            } else if let targetArray = root["modelTargets"] as? [[String: Any]] {
                for entry in targetArray {
                    guard let id = entry["id"] as? String else { continue }
                    let cap = DexDiffusionTargetCapability(
                        id: id,
                        family: (entry["family"] as? String) ?? "diffusion",
                        engine: (entry["engine"] as? String) ?? "unknown",
                        status: (entry["status"] as? String) ?? "unknown",
                        proofState: (entry["proofState"] as? String) ?? (entry["proof"] as? String) ?? "unproven",
                        reason: entry["reason"] as? String
                    )
                    parsedTargets.append(cap)
                }
            }

            return DexDiffusionCapabilitiesSnapshot(
                fetchedAt: Date(),
                configurationDegraded: degraded,
                editWorkerTarget: editTarget,
                targets: parsedTargets,
                reachable: true,
                diagnosticSummary: "Reachable · \(parsedTargets.count) registered target(s)"
            )
        } catch {
            return DexDiffusionCapabilitiesSnapshot(
                fetchedAt: Date(),
                configurationDegraded: false,
                editWorkerTarget: nil,
                targets: [],
                reachable: false,
                diagnosticSummary: "Offline / unreachable: \(error.localizedDescription)"
            )
        }
    }

    func fetchWildcards() async throws -> [DexDiffusionWildcardBank] {
        let req = URLRequest(url: baseURL.appendingPathComponent("api/wildcards"))
        let (data, http) = try await transport.send(req)
        guard (200..<300).contains(http.statusCode) else {
            throw DexDiffusionClientError.serverError(statusCode: http.statusCode, message: String(decoding: data, as: UTF8.self))
        }
        let json = try JSONSerialization.jsonObject(with: data)
        var banks: [DexDiffusionWildcardBank] = []

        if let dict = json as? [String: Any], let list = dict["wildcards"] as? [[String: Any]] {
            for item in list {
                if let name = item["name"] as? String {
                    let entries = (item["entries"] as? [String]) ?? []
                    let count = (item["count"] as? Int) ?? entries.count
                    banks.append(DexDiffusionWildcardBank(id: name, name: name, count: count, sampleEntries: Array(entries.prefix(5))))
                }
            }
        } else if let list = json as? [[String: Any]] {
            for item in list {
                if let name = item["name"] as? String {
                    let entries = (item["entries"] as? [String]) ?? []
                    let count = (item["count"] as? Int) ?? entries.count
                    banks.append(DexDiffusionWildcardBank(id: name, name: name, count: count, sampleEntries: Array(entries.prefix(5))))
                }
            }
        } else if let dict = json as? [String: Any] {
            for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
                if let entries = v as? [String] {
                    banks.append(DexDiffusionWildcardBank(id: k, name: k, count: entries.count, sampleEntries: Array(entries.prefix(5))))
                }
            }
        }
        return banks
    }

    func fetchControlledPromptMaxLength() async -> Int? {
        let req = URLRequest(url: baseURL.appendingPathComponent("api/generation-schema"))
        guard let (data, http) = try? await transport.send(req),
              (200..<300).contains(http.statusCode),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = root["properties"] as? [String: Any],
              let promptProp = props["prompt"] as? [String: Any],
              let maxLen = promptProp["maxLength"] as? Int else {
            return nil
        }
        return maxLen
    }

    /// Safe non-billable preview route (`POST /api/preview/generation`).
    func previewGeneration(payloadJSON: String) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/preview/generation"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = payloadJSON.data(using: .utf8)
        let (data, http) = try await transport.send(req)
        guard (200..<300).contains(http.statusCode) else {
            throw DexDiffusionClientError.serverError(statusCode: http.statusCode, message: String(decoding: data, as: UTF8.self))
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Explicitly gated controlled worker submission (`POST /api/actions/generate-controlled`).
    func submitControlledGeneration(
        result: CompilationResult,
        authorization: ServeAuthorizationToken
    ) async throws -> String {
        guard authorization.channel == .submitDexDiffusionControlled else {
            throw DexDiffusionClientError.unauthorizedSubmission
        }
        guard !result.proofReport.hasBlockingIssues else {
            throw DexDiffusionClientError.blockingProofIssues
        }
        var req = URLRequest(url: baseURL.appendingPathComponent("api/actions/generate-controlled"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = result.structuredPayloadJSON.data(using: .utf8)

        let (data, http) = try await transport.send(req)
        guard (200..<300).contains(http.statusCode) else {
            throw DexDiffusionClientError.serverError(statusCode: http.statusCode, message: String(decoding: data, as: UTF8.self))
        }
        return String(decoding: data, as: UTF8.self)
    }

    func cancelJob(jobId: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/jobs/\(jobId)/cancel"))
        req.httpMethod = "POST"
        let (data, http) = try await transport.send(req)
        guard (200..<300).contains(http.statusCode) else {
            throw DexDiffusionClientError.serverError(statusCode: http.statusCode, message: String(decoding: data, as: UTF8.self))
        }
    }
}
