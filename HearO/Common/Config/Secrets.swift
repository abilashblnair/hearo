import Foundation

enum Secrets {
    // API keys - reads from environment variables or local file (gitignored)
    static var assemblyAIKey: String {
        // 1. Try environment variable first
        if let key = ProcessInfo.processInfo.environment["ASSEMBLYAI_API_KEY"], !key.isEmpty {
            return key
        }
        
        // 2. Fall back to local file (gitignored, for development)
        #if DEBUG
        return SecretsLocal.assemblyAIKey
        #else
        return ""
        #endif
    }
    
    static var openAIKey: String {
        // 1. Try environment variable first
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
            return key
        }
        
        // 2. Fall back to local file (gitignored, for development)
        #if DEBUG
        return SecretsLocal.openAIKey
        #else
        return ""
        #endif
    }
}