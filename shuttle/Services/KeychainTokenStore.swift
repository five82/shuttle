import Foundation
import Security

/// The API token as a generic password in the login keychain, keyed by the
/// daemon's service name. Replaces the old UserDefaults string, which sat
/// in plain text in a plist any process could read.
final class KeychainTokenStore: TokenStore {
    private let service: String
    private let account = "spindle-api-token"

    init(service: String = Bundle.main.bundleIdentifier ?? "shuttle") {
        self.service = service
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ token: String) {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
