import SwiftUI
import AVFoundation

struct TranslationView: View {
    let originalTranscript: [TranscriptSegment]
    @State private var translatedTranscript: [TranscriptSegment]
    @State private var targetLanguage: Language?
    @State private var isTranslating: Bool = false
    let onSeekToTimestamp: (TimeInterval) -> Void
    let onLanguageChange: (Language) async -> [TranscriptSegment]?
    
    init(originalTranscript: [TranscriptSegment],
         translatedTranscript: [TranscriptSegment],
         targetLanguage: Language?,
         onSeekToTimestamp: @escaping (TimeInterval) -> Void,
         onLanguageChange: @escaping (Language) async -> [TranscriptSegment]?) {
        self.originalTranscript = originalTranscript
        self._translatedTranscript = State(initialValue: translatedTranscript)
        self._targetLanguage = State(initialValue: targetLanguage)
        self.onSeekToTimestamp = onSeekToTimestamp
        self.onLanguageChange = onLanguageChange
    }
    
    @StateObject private var ttsManager = GoogleCloudTTSManager.shared
    @StateObject private var languageManager = LanguageManager()
    @Environment(\.dismiss) private var dismiss
    @State private var showingOriginal = false
    @State private var currentSpeakingSegment: UUID?
    @State private var isAnyAudioPlaying = false
    @State private var showLanguageSelection = false
    
    var selectedLanguage: Language? {
        targetLanguage
    }
    
    var englishLanguage: Language? {
        languageManager.languages.first { $0.languageCode == "en" && $0.countryCode == "US" } 
        ?? languageManager.languages.first { $0.languageCode == "en" }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            headerView
            
            // Content
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    ForEach(showingOriginal ? originalTranscript : translatedTranscript, id: \.id) { segment in
                        TranslationSegmentCard(
                            segment: segment,
                            isOriginal: showingOriginal,
                            isSpeaking: currentSpeakingSegment == segment.id,
                            englishLanguage: englishLanguage,
                            selectedLanguage: selectedLanguage,
                            ttsManager: ttsManager,
                            onSeek: { onSeekToTimestamp(segment.startTime) },
                            onSpeak: { speakSegment(segment) },
                            onUpdateSpeakingState: { segmentId in
                                currentSpeakingSegment = segmentId
                                isAnyAudioPlaying = segmentId != nil
                            }
                        )
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Translation")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .navigationDestination(isPresented: $showLanguageSelection) {
            LanguageSelectionView(selectedLanguage: targetLanguage) { language in
                showLanguageSelection = false
                Task {
                    await changeLanguage(to: language)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    // Change Language Button
                    Button(action: { showLanguageSelection = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "globe.badge.chevron.backward")
                                .font(.system(size: 16, weight: .medium))
                            Text("Change")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.1))
                        .foregroundColor(.purple)
                        .cornerRadius(8)
                    }
                    .disabled(isTranslating)
                    
                    // Stop Audio Button
                    if isAnyAudioPlaying {
                        Button(action: stopAllAudio) {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.circle.fill")
                                    .font(.system(size: 16, weight: .medium))
                                Text("Stop")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(8)
                        }
                    }
                    
                    // Toggle View Button
                    Button(action: toggleLanguage) {
                        HStack(spacing: 4) {
                            Image(systemName: showingOriginal ? "translate" : "doc.text")
                                .font(.system(size: 16, weight: .medium))
                            Text(showingOriginal ? "Translation" : "Original")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundColor(.accentColor)
                        .cornerRadius(8)
                    }
                }
            }
        }
        .onDisappear {
            // Stop all audio when view disappears
            stopAllAudio()
        }
        .onAppear {
            // Ensure TTS manager is properly initialized
            if ttsManager.isPlaying {
                isAnyAudioPlaying = true
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target Language")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        if let language = selectedLanguage {
                            Text(language.flag)
                                .font(.system(size: 20))
                            
                            Text(language.displayName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                        } else {
                            Text("🌐 \(targetLanguage?.name ?? "Unknown")")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                }
                
                Spacer()
                
                // Global Status
                if isTranslating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Translating...")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                } else if ttsManager.isSpeaking {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Speaking...")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            // Stats
            HStack {
                StatView(title: "Segments", value: "\(translatedTranscript.count)")
                
                Divider()
                    .frame(height: 20)
                
                StatView(title: "Duration", value: formatDuration())
                
                Spacer()
                
                // Current View Indicator
                HStack(spacing: 8) {
                    Image(systemName: showingOriginal ? "doc.text" : "translate")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.accentColor)
                    Text(showingOriginal ? "Original" : "Translation")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }
    
    // MARK: - Actions
    
    private func toggleLanguage() {
        // Stop any playing audio when switching views
        stopAllAudio()
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showingOriginal.toggle()
        }
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func speakSegment(_ segment: TranscriptSegment) {
        // Stop any currently playing audio
        stopAllAudio()
        
        // Set the current speaking segment
        currentSpeakingSegment = segment.id
        isAnyAudioPlaying = true
    }
    
    private func stopAllAudio() {
        ttsManager.stop()
        currentSpeakingSegment = nil
        isAnyAudioPlaying = false
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func formatDuration() -> String {
        guard let lastSegment = translatedTranscript.last else { return "0:00" }
        let totalSeconds = Int(lastSegment.endTime)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Language Change
    
    @MainActor
    private func changeLanguage(to newLanguage: Language) async {
        // Stop any playing audio first
        stopAllAudio()
        
        // Update UI state
        isTranslating = true
        targetLanguage = newLanguage
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        print("🔄 Changing translation language to: \(newLanguage.name)")
        
        do {
            // Call the language change callback to get new translation
            if let newTranslation = await onLanguageChange(newLanguage) {
                translatedTranscript = newTranslation
                
                // Switch to translation view if currently showing original
                if showingOriginal {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showingOriginal = false
                    }
                }
                
                print("✅ Successfully changed to \(newLanguage.name) with \(newTranslation.count) segments")
            } else {
                print("❌ Failed to get translation for \(newLanguage.name)")
            }
        } catch {
            print("❌ Error changing language: \(error)")
        }
        
        isTranslating = false
    }
}

// MARK: - Translation Segment Card

struct TranslationSegmentCard: View {
    let segment: TranscriptSegment
    let isOriginal: Bool
    let isSpeaking: Bool
    let englishLanguage: Language?
    let selectedLanguage: Language?
    let ttsManager: GoogleCloudTTSManager
    let onSeek: () -> Void
    let onSpeak: () -> Void
    let onUpdateSpeakingState: (UUID?) -> Void
    
    @State private var isSpeakingThis = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .center) {
                // Timestamp
                Button(action: onSeek) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 12, weight: .medium))
                        Text(segment.startTime.formattedHMS())
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Speaker (if available)
                if let speaker = segment.speaker, !speaker.isEmpty {
                    Text("• \(speaker)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Speak button
                Button(action: handleSpeak) {
                    HStack(spacing: 4) {
                        Image(systemName: isSpeakingThis ? "waveform.path" : "speaker.2")
                            .font(.system(size: 14, weight: .medium))
                        Text(isSpeakingThis ? "Speaking..." : "Speak")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isSpeakingThis ? Color.orange.opacity(0.1) : Color.green.opacity(0.1))
                    .foregroundColor(isSpeakingThis ? .orange : .green)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isSpeakingThis)
            }
            
            // Text content
            Text(segment.text)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isOriginal ? Color(.tertiarySystemGroupedBackground) : Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSpeakingThis ? Color.orange : Color.clear, lineWidth: 2)
                )
        )
        .scaleEffect(isSpeakingThis ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSpeakingThis)
        .onChange(of: isSpeaking) { newValue in
            isSpeakingThis = newValue
        }
    }
    
    // MARK: - TTS Methods
    
    private func handleSpeak() {
        onSpeak() // Notify parent to stop other audio
        
        guard let targetLanguage = isOriginal ? englishLanguage : selectedLanguage else {
            print("❌ No target language available for TTS. isOriginal: \(isOriginal), englishLanguage: \(englishLanguage?.name ?? "nil"), selectedLanguage: \(selectedLanguage?.name ?? "nil")")
            return
        }
        
        isSpeakingThis = true
        onUpdateSpeakingState(segment.id)
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        print("🗣️ Speaking text: '\(segment.text)' in language: \(targetLanguage.name) (\(targetLanguage.languageCode)) with TTS: \(targetLanguage.googleTTSLanguageCode ?? "fallback") / \(targetLanguage.googleTTSVoice ?? "fallback")")
        
        ttsManager.speak(text: segment.text, language: targetLanguage) { [segment] success in
            DispatchQueue.main.async {
                self.isSpeakingThis = false
                self.onUpdateSpeakingState(nil)
                
                if success {
                    print("✅ Successfully spoke text for segment \(segment.id)")
                } else {
                    print("❌ Failed to speak text for segment \(segment.id)")
                }
            }
        }
    }
}

// MARK: - Stat View

struct StatView: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
            
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}

// The formattedHMS() extension is already defined in Summary.swift

// MARK: - Preview

#Preview {
    let sampleSegments = [
        TranscriptSegment(
            id: UUID(),
            speaker: "John",
            text: "Hello, how are you today?",
            startTime: 0.0,
            endTime: 5.0
        ),
        TranscriptSegment(
            id: UUID(),
            speaker: "Alice",
            text: "I'm doing great, thank you for asking!",
            startTime: 5.0,
            endTime: 10.0
        )
    ]
    
    let translatedSegments = [
        TranscriptSegment(
            id: UUID(),
            speaker: "John",
            text: "Hola, ¿cómo estás hoy?",
            startTime: 0.0,
            endTime: 5.0
        ),
        TranscriptSegment(
            id: UUID(),
            speaker: "Alice",
            text: "Estoy muy bien, ¡gracias por preguntar!",
            startTime: 5.0,
            endTime: 10.0
        )
    ]
    
    NavigationStack {
        TranslationView(
            originalTranscript: sampleSegments,
            translatedTranscript: translatedSegments,
            targetLanguage: Language(
                id: "es-ES",
                name: "Spanish (Spain)",
                nativeName: "Español",
                languageCode: "es",
                countryCode: "ES",
                localeIdentifier: "es-ES",
                flag: "🇪🇸",
                ttsVoices: ["com.apple.ttsbundle.Monica-compact"],
                googleTTSLanguageCode: "es-ES",
                googleTTSVoice: "es-ES-Studio-C",
                category: "Popular",
                isPopular: true
            ),
            onSeekToTimestamp: { _ in },
            onLanguageChange: { _ in return nil }
        )
    }
}
