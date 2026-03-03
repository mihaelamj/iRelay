import Foundation
import Shared

// MARK: - Keychain Store

public struct KeychainStore: Sendable {
    private let service: String

    public init(service: String = "com.swiftclaw") {
        self.service = service
    }

    /// Store a secret in the Keychain.
    public func set(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        // Delete any existing item first
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SwiftClawError.secretNotFound("Keychain set failed: \(status)")
        }
    }

    /// Retrieve a secret from the Keychain.
    public func get(_ key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw SwiftClawError.secretNotFound("Keychain get failed: \(status)")
        }
        return String(data: data, encoding: .utf8)
    }

    /// Delete a secret from the Keychain.
    public func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SwiftClawError.secretNotFound("Keychain delete failed: \(status)")
        }
    }

    // MARK: - Convenience for API Keys

    /// Store an API key for a provider (e.g., "claude", "openai").
    public func setAPIKey(_ key: String, provider: String) throws {
        try set(key, for: "apikey.\(provider)")
    }

    /// Retrieve an API key for a provider.
    public func apiKey(for provider: String) throws -> String? {
        try get("apikey.\(provider)")
    }
}
