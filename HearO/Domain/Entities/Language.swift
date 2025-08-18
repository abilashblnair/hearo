import Foundation

struct Language: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let nativeName: String
    let languageCode: String
    let countryCode: String
    let localeIdentifier: String
    let flag: String
    let ttsVoices: [String] // Apple TTS voices
    let googleTTSLanguageCode: String? // Google TTS language code
    let googleTTSVoice: String? // Google TTS voice name
    let category: String
    let isPopular: Bool
    
    var displayName: String {
        if name == nativeName {
            return name
        } else {
            return "\(name) (\(nativeName))"
        }
    }
    
    var locale: Locale {
        return Locale(identifier: localeIdentifier)
    }
}

struct LanguagesResponse: Codable {
    let languages: [Language]
}

final class LanguageManager: ObservableObject {
    @Published var languages: [Language] = []
    @Published var isLoading = false
    
    init() {
        loadLanguages()
    }
    
    private func loadLanguages() {
        isLoading = true
        
        guard let url = Bundle.main.url(forResource: "supported_languages", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("❌ Failed to load supported_languages.json")
            isLoading = false
            return
        }
        
        do {
            let response = try JSONDecoder().decode(LanguagesResponse.self, from: data)
            DispatchQueue.main.async {
                self.languages = response.languages
                self.isLoading = false
                print("✅ Loaded \(self.languages.count) languages")
            }
        } catch {
            print("❌ Failed to decode languages: \(error)")
            isLoading = false
        }
    }
    
    var popularLanguages: [Language] {
        return languages.filter { $0.isPopular }
    }
    
    var groupedLanguages: [String: [Language]] {
        return Dictionary(grouping: languages) { $0.category }
    }
    
    var categories: [String] {
        let allCategories = Set(languages.map { $0.category })
        return allCategories.sorted { category1, category2 in
            if category1 == "Popular" { return true }
            if category2 == "Popular" { return false }
            return category1 < category2
        }
    }
    
    func language(for id: String) -> Language? {
        return languages.first { $0.id == id }
    }
    
    func languageByLocale(_ localeIdentifier: String) -> Language? {
        return languages.first { $0.localeIdentifier == localeIdentifier }
    }
    
    func searchLanguages(query: String) -> [Language] {
        guard !query.isEmpty else { return languages }
        
        let lowercasedQuery = query.lowercased()
        return languages.filter { language in
            language.name.lowercased().contains(lowercasedQuery) ||
            language.nativeName.lowercased().contains(lowercasedQuery) ||
            language.languageCode.lowercased().contains(lowercasedQuery)
        }
    }
}
