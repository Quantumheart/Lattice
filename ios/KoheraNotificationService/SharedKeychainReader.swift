import Foundation

struct SharedKeychainReader {
    static let accessGroup = "group.io.github.quantumheart.kohera"

    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            NSLog("[KoheraNSE] Keychain read failed for %@: %d", key, status)
            return nil
        }
        return value
    }
}
