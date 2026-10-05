import Foundation
import Security

enum KeychainService {
    private static let service = "com.synapsonic.lumo"
    static func saveAPIKey(_ key:String) {
        let data = Data(key.utf8)
        let q:[String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"anthropic-api-key"]
        SecItemDelete(q as CFDictionary)
        var n = q; n[kSecValueData as String] = data; SecItemAdd(n as CFDictionary,nil)
    }
    static func saveGeminiAPIKey(_ key:String) {
        save(key, account: "gemini-api-key")
    }
    static func geminiAPIKey()->String? { read(account: "gemini-api-key") }

    private static func save(_ key:String, account:String) {
        let data = Data(key.utf8)
        let q:[String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]
        SecItemDelete(q as CFDictionary); var n=q; n[kSecValueData as String]=data; SecItemAdd(n as CFDictionary,nil)
    }
    private static func read(account:String)->String? {
        let q:[String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var r:AnyObject?; guard SecItemCopyMatching(q as CFDictionary,&r)==errSecSuccess, let d=r as? Data else{return nil}; return String(data:d,encoding:.utf8)
    }
    static func apiKey()->String? {
        let q:[String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"anthropic-api-key",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var r:AnyObject?; guard SecItemCopyMatching(q as CFDictionary,&r)==errSecSuccess, let d = r as? Data else{return nil}; return String(data:d,encoding:.utf8)
    }
}
