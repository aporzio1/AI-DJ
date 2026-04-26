import Foundation
import Security

/// Thin wrapper over Security framework's Keychain for generic passwords.
/// Used for API keys (OpenAI) and other secrets that should never be in UserDefaults or source.
///
/// Items are written with `kSecAttrSynchronizable: true` so they ride iCloud
/// Keychain across the user's signed-in devices when the user has iCloud
/// Keychain enabled in System Settings. Reads/deletes use
/// `kSecAttrSynchronizableAny` so values written by an older non-sync build
/// on this device are still found and get rewritten as synchronizable on the
/// next `set`.
enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "com.andrewporzio.patter"

    static func set(_ value: String, forKey key: String) {
        let data = Data(value.utf8)

        // Remove any existing entry — sync or local — so we never end up with
        // both a local and a synchronizable copy of the same key. Ignored if
        // nothing matches.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: true
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
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
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// One-shot migration: if a non-synchronizable copy of `key` exists on
    /// this device (left over from a build before iCloud Keychain sync), copy
    /// it into the synchronizable store and delete the local one. Idempotent
    /// — safe to call on every launch.
    static func migrateToSynchronizable(_ key: String) {
        let readLocal: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        guard SecItemCopyMatching(readLocal as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return
        }

        set(value, forKey: key)

        let deleteLocal: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false
        ]
        SecItemDelete(deleteLocal as CFDictionary)
    }
}

enum KeychainKey {
    static let openAIAPIKey = "openai.apiKey"
}
