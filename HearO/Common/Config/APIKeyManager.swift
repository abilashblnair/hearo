import Foundation
import Security

/// Secure API key management using Keychain
class APIKeyManager {
    private static let serviceName = "com.hearo.apikeys"
    
    static let shared = APIKeyManager()
    private init() {}
    
    // MARK: - API Key Storage
    
    /// Store API key securely in Keychain
    func storeAPIKey(_ key: String, for service: APIService) -> Bool {
        let data = Data(key.utf8)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: service.rawValue,
            kSecValueData as String: data
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Retrieve API key from Keychain
    func getAPIKey(for service: APIService) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: service.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return key
    }
    
    /// Delete API key from Keychain
    func deleteAPIKey(for service: APIService) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: service.rawValue
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }
}

// MARK: - API Services

enum APIService: String, CaseIterable {
    case openAI = "openai_key"
    case assemblyAI = "assemblyai_key"

    var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .assemblyAI:
            return "AssemblyAI"
        }
    }
}

// MARK: - Convenience Extensions

extension APIKeyManager {
    
    /// Get OpenAI API key
    var openAIKey: String? {
        return getAPIKey(for: .openAI)
    }
    
    /// Get AssemblyAI API key
    var assemblyAIKey: String? {
        return getAPIKey(for: .assemblyAI)
    }
    
    /// Store OpenAI API key
    func storeOpenAIKey(_ key: String) -> Bool {
        return storeAPIKey(key, for: .openAI)
    }
    
    /// Store AssemblyAI API key
    func storeAssemblyAIKey(_ key: String) -> Bool {
        return storeAPIKey(key, for: .assemblyAI)
    }
}
