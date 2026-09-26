import Foundation
import Security

enum TokenKeychain {
    private static let service = "com.liteu.app"

    struct SaveError: LocalizedError {
        var status: OSStatus

        var errorDescription: String? {
            "无法保存登录信息（\(status)）"
        }
    }

    static func load(account: String) -> String? {
        var query = base(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, account: String) throws {
        delete(account: account)
        var query = base(account: account)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SaveError(status: status) }
    }

    static func delete(account: String) {
        SecItemDelete(base(account: account) as CFDictionary)
    }

    private static func base(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
