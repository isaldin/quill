import Foundation
import Security

enum KeychainStore {
    private static let service = "dev.saldin.openwhisper"
    private static let account = "openrouter"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Пустая строка удаляет ключ.
    static func save(_ value: String) {
        SecItemDelete(baseQuery as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var query = baseQuery
        query[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }
}
