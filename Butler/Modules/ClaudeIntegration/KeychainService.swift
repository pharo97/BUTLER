import Security
import Foundation

// MARK: - KeychainService

/// Secure storage for API keys in the macOS Keychain.
///
/// Each provider gets its own Keychain entry keyed by `AIProviderType.keychainAccount`.
/// The key value is never held in memory beyond the immediate call site.
enum KeychainService {

    private static let service = "com.butler.app"

    // MARK: - Save

    /// Writes `key` for `provider`, replacing any existing value.
    static func save(_ key: String, for provider: AIProviderType) throws {
        try save(key, account: provider.keychainAccount)
    }

    static func save(_ key: String, account: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        // Delete first so we can do a clean Add instead of an Update.
        let deleteQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData:   data,
            kSecAttrLabel:   "BUTLER API Key (\(account))"
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    // MARK: - Load

    /// Returns the stored key for `provider`, or throws if none is saved.
    static func load(for provider: AIProviderType) throws -> String {
        try load(account: provider.keychainAccount)
    }

    static func load(account: String) throws -> String {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { throw KeychainError.notFound }
        guard let data = result as? Data,
              let key  = String(data: data, encoding: .utf8)
        else { throw KeychainError.decodingFailed }
        return key
    }

    // MARK: - Delete

    /// Removes the stored key for `provider`.
    static func delete(for provider: AIProviderType) {
        delete(account: provider.keychainAccount)
    }

    static func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Errors

    enum KeychainError: Error, LocalizedError {
        case encodingFailed
        case saveFailed(OSStatus)
        case notFound
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .encodingFailed:        return "Failed to encode API key."
            case .saveFailed(let code): return "Keychain save failed (OSStatus \(code))."
            case .notFound:             return "No API key found. Please add one in settings."
            case .decodingFailed:       return "Failed to decode stored API key."
            }
        }
    }
}
