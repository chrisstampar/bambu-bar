import Foundation
import Security

/// The printer's LAN access code, kept in the keychain per serial number.
enum Keychain {
    private static let service = "dev.rolottr.BambuBar.access-code"

    /// The item for a printer. The App Store build keeps its codes in the data protection keychain, under its App
    /// Store identity: the login keychain would ask for permission (and block launch until answered) whenever it
    /// met a code saved by the differently signed GitHub build. Its sandbox starts with settings of its own anyway.
    private static func item(_ serial: String) -> [String: Any] {
        var item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serial,
        ]
        #if APP_STORE
            item[kSecUseDataProtectionKeychain as String] = true
        #endif
        return item
    }

    static func accessCode(for serial: String) -> String? {
        var query = item(serial)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setAccessCode(_ code: String, for serial: String) {
        let data = Data(code.utf8)
        if SecItemUpdate(item(serial) as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var add = item(serial)
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "Bambu Bar printer access code"
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func removeAccessCode(for serial: String) {
        SecItemDelete(item(serial) as CFDictionary)
    }
}
