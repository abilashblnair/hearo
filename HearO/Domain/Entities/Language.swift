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
    let isPremium: Bool // Whether this language requires premium access
    
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
    
    /// Check if this language is accessible for the current user based on subscription status
    func isAccessible(isPremium: Bool) -> Bool {
        return !self.isPremium || isPremium
    }
    
    /// Check if this language is accessible using FeatureManager
    @MainActor
    func isAccessible(with featureManager: FeatureManager) -> Bool {
        return featureManager.hasAccessToLanguage(languageCode)
    }
}

struct LanguagesResponse: Codable {
    let languages: [Language]
}

@MainActor
final class LanguageManager: ObservableObject {
    @Published var languages: [Language] = []
    @Published var isLoading = false
    
    private let featureManager = FeatureManager.shared
    
    init() {
        loadLanguages()
    }
    
    private func loadLanguages() {
        isLoading = true
        
        guard let url = Bundle.main.url(forResource: "supported_languages", withExtension: "json") else {
            isLoading = false
            return
        }
        
        guard let data = try? Data(contentsOf: url) else {
            isLoading = false
            return
        }
        
        do {
            let response = try JSONDecoder().decode(LanguagesResponse.self, from: data)
            DispatchQueue.main.async {
                self.languages = response.languages
                self.isLoading = false
            }
        } catch {
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
    
    /// Get languages filtered by accessibility based on current subscription status
    var accessibleLanguages: [Language] {
        return languages.filter { $0.isAccessible(with: featureManager) }
    }
    
    /// Get premium languages that are not accessible to free users
    var premiumLanguages: [Language] {
        return languages.filter { $0.isPremium && !$0.isAccessible(with: featureManager) }
    }
    
    /// Get popular languages filtered by accessibility
    var accessiblePopularLanguages: [Language] {
        return languages.filter { $0.isPopular && $0.isAccessible(with: featureManager) }
    }
    
    /// Get grouped languages with accessibility filtering
    var accessibleGroupedLanguages: [String: [Language]] {
        let accessibleLangs = accessibleLanguages
        return Dictionary(grouping: accessibleLangs) { $0.category }
    }
}
