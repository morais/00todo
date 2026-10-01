import Foundation
import Security

/// Session details shared with the share extension. The bearer token remains in
/// Keychain, never in App Group UserDefaults or the shared file container.
enum SharedSession {
    private static let tokenService = "00todo.share-api-token"

    static var group: String? { Bundle.main.object(forInfoDictionaryKey: "TodoAppGroup") as? String }

    static var tenantId: String? {
        guard let group else { return nil }
        return UserDefaults(suiteName: group)?.string(forKey: "shareTenantId")
    }

    static var serverAddress: String? {
        guard let group else { return nil }
        return UserDefaults(suiteName: group)?.string(forKey: "shareServerAddress")
    }

    static func publish(tenantId: String, serverAddress: String, token: String) throws {
        guard let group, let defaults = UserDefaults(suiteName: group) else { return }
        // Keep the offline handoff available even if shared Keychain access is
        // temporarily unavailable; the extension can still queue a task.
        defaults.set(tenantId, forKey: "shareTenantId")
        defaults.set(serverAddress, forKey: "shareServerAddress")
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: tokenService,
                                    kSecAttrAccessGroup as String: group]
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var input = query
            input.merge(attributes) { _, new in new }
            status = SecItemAdd(input as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    static func readToken() -> String? {
        guard let group else { return nil }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: tokenService,
                                    kSecAttrAccessGroup as String: group,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clear() {
        guard let group else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: tokenService,
                                    kSecAttrAccessGroup as String: group]
        SecItemDelete(query as CFDictionary)
        let defaults = UserDefaults(suiteName: group)
        defaults?.removeObject(forKey: "shareTenantId")
        defaults?.removeObject(forKey: "shareServerAddress")
    }
}
