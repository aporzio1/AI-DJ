import Foundation
import Security

/// Thin wrapper over Security framework's Keychain for generic passwords.
/// Used for API keys (OpenAI) and other secrets that should never be in UserDefaults or source.
enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "com.andrewporzio.aidj"

    static func set(_ value: String, forKey key: String) {
        let data = Data(value.utf8)

        // Try update first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainKey {
    static let openAIAPIKey = "openai.apiKey"
    static let spotifyAccessToken = "spotify.accessToken"
    static let spotifyRefreshToken = "spotify.refreshToken"
    /// ISO-8601 timestamp of access-token expiration. Stored as a string for
    /// simplicity — the Keychain wrapper is generic-password-only.
    static let spotifyExpiresAt = "spotify.expiresAt"
    /// Space-separated scope string returned in the token exchange. Logged on
    /// app launch so we can diagnose 403s that are actually missing-scope
    /// issues without forcing the user to reconnect.
    static let spotifyScope = "spotify.scope"
}
