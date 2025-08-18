import Foundation

enum Secrets {
    // Read API key from Info.plist with key "ASSEMBLYAI_API_KEY" or from environment variable, or fallback to empty
    static var assemblyAIKey: String {
        if let key = Bundle.main.object(forInfoDictionaryKey: "ASSEMBLYAI_API_KEY") as? String, key.isEmpty == false {
            return key
        }
        if let env = ProcessInfo.processInfo.environment["ASSEMBLYAI_API_KEY"], env.isEmpty == false {
            return env
        }
        // Optionally allow UserDefaults override for debugging
        if let override = UserDefaults.standard.string(forKey: "ASSEMBLYAI_API_KEY"), override.isEmpty == false {
            return override
        }
        return ""
    }
    
    // Read OpenAI API key from Info.plist with key "OPENAI_API_KEY" or from environment variable, or fallback to empty
    static var openAIKey: String {
        if let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String, key.isEmpty == false {
            return key
        }
        if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], env.isEmpty == false {
            return env
        }
        // Optionally allow UserDefaults override for debugging
        if let override = UserDefaults.standard.string(forKey: "OPENAI_API_KEY"), override.isEmpty == false {
            return override
        }
        return ""
    }
}
