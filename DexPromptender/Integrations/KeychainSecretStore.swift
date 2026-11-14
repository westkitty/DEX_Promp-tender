import Foundation
import Security

enum APIKeyProvider: String, CaseIterable, Identifiable, Codable {
    case xai = "xai_api_key"
    case openAI = "openai_api_key"
    case gemini = "gemini_api_key"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .xai: return "xAI (Grok Imagine)"
        case .openAI: return "OpenAI (GPT / GPT Image)"
        case .gemini: return "Google Gemini (Nano Banana / Veo / Omni)"
        }
    }
}

protocol SecretStoreProtocol {
    func saveSecret(_ value: String, for provider: APIKeyProvider) throws
    func loadSecret(for provider: APIKeyProvider) throws -> String?
    func deleteSecret(for provider: APIKeyProvider) throws
    func hasSecret(for provider: APIKeyProvider) -> Bool
}

enum KeychainSecretError: LocalizedError {
    case unhandledStatus(OSStatus)
    case encodingError

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            return "macOS Keychain operation failed with status \(status)."
        case .encodingError:
            return "Failed to UTF-8 encode API key."
        }
    }
}

/// Native macOS Keychain secret storage isolated under `com.andrew.dexpromptender.secrets`.
final class KeychainSecretStore: SecretStoreProtocol {
    private let service: String

    init(service: String = "com.andrew.dexpromptender.secrets") {
        self.service = service
    }

    func saveSecret(_ value: String, for provider: APIKeyProvider) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteSecret(for: provider)
            return
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw KeychainSecretError.encodingError
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainSecretError.unhandledStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainSecretError.unhandledStatus(updateStatus)
        }
    }

    func loadSecret(for provider: APIKeyProvider) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainSecretError.unhandledStatus(status)
        }
        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            return nil
        }
        return secret
    }

    func deleteSecret(for provider: APIKeyProvider) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretError.unhandledStatus(status)
        }
    }

    func hasSecret(for provider: APIKeyProvider) -> Bool {
        (try? loadSecret(for: provider))?.isEmpty == false
    }
}

/// Deterministic in-memory secret store used for unit & integration tests without Keychain dialogs.
final class InMemorySecretStore: SecretStoreProtocol {
    private var storage: [APIKeyProvider: String] = [:]

    func saveSecret(_ value: String, for provider: APIKeyProvider) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            storage.removeValue(forKey: provider)
        } else {
            storage[provider] = trimmed
        }
    }

    func loadSecret(for provider: APIKeyProvider) throws -> String? {
        storage[provider]
    }

    func deleteSecret(for provider: APIKeyProvider) throws {
        storage.removeValue(forKey: provider)
    }

    func hasSecret(for provider: APIKeyProvider) -> Bool {
        storage[provider]?.isEmpty == false
    }
}
