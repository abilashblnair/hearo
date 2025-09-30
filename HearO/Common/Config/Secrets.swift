import Foundation

enum Secrets {
    // API keys - set via Xcode scheme environment variables
    static var assemblyAIKey: String {
        // Read from environment variable
        if let key = ProcessInfo.processInfo.environment["ASSEMBLYAI_API_KEY"], !key.isEmpty {
            return key
        }
        return ""
    }
    
    static var openAIKey: String {
        // Read from environment variable
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
            return key
        }
        return ""
    }
}
