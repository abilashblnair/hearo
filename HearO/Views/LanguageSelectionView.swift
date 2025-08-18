import SwiftUI

struct LanguageSelectionView: View {
    @StateObject private var languageManager = LanguageManager()
    @State private var searchText = ""
    @State private var selectedLanguage: Language?
    @State private var animateSelection = false
    @Environment(\.dismiss) private var dismiss
    
    let onLanguageSelected: (Language) -> Void
    
    init(selectedLanguage: Language? = nil, onLanguageSelected: @escaping (Language) -> Void) {
        self._selectedLanguage = State(initialValue: selectedLanguage)
        self.onLanguageSelected = onLanguageSelected
    }
    
    var body: some View {
        VStack(spacing: 0) {
                // Search Bar
                searchBarView
                
                // Content
                if languageManager.isLoading {
                    loadingView
                } else {
                    languageListView
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Select Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
    }
    
    // MARK: - Search Bar
    
    private var searchBarView: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16, weight: .medium))
                
                TextField("Search languages...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading languages...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Language List
    
    private var languageListView: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                let filteredLanguages = languageManager.searchLanguages(query: searchText)
                
                if searchText.isEmpty {
                    // Show categorized view when not searching
                    ForEach(languageManager.categories, id: \.self) { category in
                        if let languages = languageManager.groupedLanguages[category], !languages.isEmpty {
                            languageCategorySection(category: category, languages: languages)
                        }
                    }
                } else {
                    // Show search results
                    if filteredLanguages.isEmpty {
                        emptySearchView
                    } else {
                        searchResultsSection(languages: filteredLanguages)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 100) // Extra padding for better scrolling
        }
    }
    
    private func languageCategorySection(category: String, languages: [Language]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category Header
            HStack {
                categoryIcon(for: category)
                
                Text(category)
                    .font(.title2.weight(.bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(languages.count)")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 4)
            
            // Languages Grid
            if category == "Popular" {
                popularLanguagesGrid(languages: languages)
            } else {
                regularLanguagesGrid(languages: languages)
            }
        }
    }
    
    private func categoryIcon(for category: String) -> some View {
        Group {
            switch category {
            case "Popular":
                Image(systemName: "star.fill")
                    .foregroundColor(.orange)
            case "European":
                Image(systemName: "building.columns")
                    .foregroundColor(.blue)
            case "Asian":
                Image(systemName: "globe.asia.australia")
                    .foregroundColor(.green)
            case "Middle Eastern":
                Image(systemName: "moon.fill")
                    .foregroundColor(.purple)
            default:
                Image(systemName: "globe")
                    .foregroundColor(.gray)
            }
        }
        .font(.system(size: 20, weight: .medium))
    }
    
    private func popularLanguagesGrid(languages: [Language]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            ForEach(languages) { language in
                PopularLanguageCard(
                    language: language,
                    isSelected: selectedLanguage?.id == language.id,
                    onTap: { selectLanguage(language) }
                )
            }
        }
    }
    
    private func regularLanguagesGrid(languages: [Language]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 1), spacing: 8) {
            ForEach(languages) { language in
                RegularLanguageCard(
                    language: language,
                    isSelected: selectedLanguage?.id == language.id,
                    onTap: { selectLanguage(language) }
                )
            }
        }
    }
    
    private func searchResultsSection(languages: [Language]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                Text("Search Results")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(languages.count)")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 4)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 1), spacing: 8) {
                ForEach(languages) { language in
                    RegularLanguageCard(
                        language: language,
                        isSelected: selectedLanguage?.id == language.id,
                        onTap: { selectLanguage(language) }
                    )
                }
            }
        }
    }
    
    private var emptySearchView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.secondary)
            
            VStack(spacing: 4) {
                Text("No languages found")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Try adjusting your search terms")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    // MARK: - Actions
    
    private func selectLanguage(_ language: Language) {
        selectedLanguage = language
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Animate selection
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            animateSelection = true
        }
        
        // Delay callback to show selection animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onLanguageSelected(language)
        }
    }
}

// MARK: - Popular Language Card

struct PopularLanguageCard: View {
    let language: Language
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Flag
                Text(language.flag)
                    .font(.system(size: 36))
                
                // Language Name
                VStack(spacing: 2) {
                    Text(language.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(language.nativeName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected ? Color.accentColor : Color.clear,
                                lineWidth: 2
                            )
                    )
            )
            .scaleEffect(isSelected ? 0.98 : 1.0)
            .shadow(color: .black.opacity(0.1), radius: isSelected ? 8 : 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Regular Language Card

struct RegularLanguageCard: View {
    let language: Language
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Flag
                Text(language.flag)
                    .font(.system(size: 24))
                
                // Language Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    if language.name != language.nativeName {
                        Text(language.nativeName)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Selection Indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 20))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? Color.accentColor : Color.clear,
                                lineWidth: 1.5
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    LanguageSelectionView { language in
        print("Selected: \(language.name)")
    }
}
