import SwiftUI
import AVFoundation

struct TranslationView: View {
    let originalTranscript: [TranscriptSegment]
    let translatedTranscript: [TranscriptSegment]
    let targetLanguage: Language?
    let onSeekToTimestamp: (TimeInterval) -> Void
    let onChangeLanguageRequest: () -> Void

    @StateObject private var ttsManager = GoogleCloudTTSManager.shared
    @StateObject private var languageManager = LanguageManager()
    @Environment(\.dismiss) private var dismiss
    @State private var showingOriginal = false
    @State private var currentSpeakingSegment: UUID?
    @State private var isAnyAudioPlaying = false
    
    // Toast state for copy functionality
    @State private var showToast = false
    @State private var toastMessage = ""

    var selectedLanguage: Language? {
        targetLanguage
    }

    var englishLanguage: Language? {
        languageManager.languages.first { $0.languageCode == "en" && $0.countryCode == "US" }
        ?? languageManager.languages.first { $0.languageCode == "en" }
    }

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                // iPad centered layout
                GeometryReader { geometry in
                    HStack {
                        Spacer()

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
                                            onCopyText: copyTextToClipboard,
                                                                        onUpdateSpeakingState: { segmentId in
                                DispatchQueue.main.async {
                                    currentSpeakingSegment = segmentId
                                    isAnyAudioPlaying = segmentId != nil
                                }
                            }
                                        )
                                    }
                                }
                                .padding(24)
                            }
                        }
                        .frame(maxWidth: min(geometry.size.width * 0.8, 1000))

                        Spacer()
                    }
                }
            } else {
                // iPhone layout
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
                                    onCopyText: copyTextToClipboard,
                                                                onUpdateSpeakingState: { segmentId in
                                DispatchQueue.main.async {
                                    currentSpeakingSegment = segmentId
                                    isAnyAudioPlaying = segmentId != nil
                                }
                            }
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .overlay(
            // Toast overlay
            VStack {
                Spacer()
                if showToast {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                        Text(toastMessage)
                            .foregroundColor(.white)
                            .font(.callout.weight(.medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.8))
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showToast)
                }
            }
            .padding(.bottom, 50)
        )
        .navigationTitle("Translation")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)

        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    // Change Language Button
                    Button(action: {
                        // Go back to TranscriptResultView and trigger language selection
                        onChangeLanguageRequest()
                        dismiss()
                    }) {
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

                // Global TTS Status  
                if ttsManager.isSpeaking {
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

                // Only show duration if it's valid
                let duration = formatDuration()
                if duration != "Unknown" {
                    Divider()
                        .frame(height: 20)

                    StatView(title: "Duration", value: duration)
                }

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

    // MARK: - Copy Functionality
    
    private func copyTextToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        toastMessage = "Text copied"
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            showToast = true
        }
        
        // Auto-hide toast after 2 seconds
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            await MainActor.run {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showToast = false
                }
            }
        }
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

        // Set the current speaking segment immediately
        currentSpeakingSegment = segment.id
        isAnyAudioPlaying = true

        // The actual TTS will be handled by the child component
        // State will be cleared when TTS completes via onUpdateSpeakingState callback
    }

    private func stopAllAudio() {
        ttsManager.stop()
        currentSpeakingSegment = nil
        isAnyAudioPlaying = false

        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }

    private func formatDuration() -> String {
        guard let lastSegment = translatedTranscript.last,
              lastSegment.endTime > 0 else {
            return ""
        }

        let totalSeconds = Int(lastSegment.endTime)
        guard totalSeconds > 0 else { return "" }

        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
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
    let onCopyText: (String) -> Void
    let onUpdateSpeakingState: (UUID?) -> Void

    @State private var isSpeakingThis = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .center) {
                // Timestamp (only show if valid)
                if segment.startTime > 0 {
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
                }

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
                .onLongPressGesture {
                    onCopyText(segment.text)
                }
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
        .onChange(of: isSpeaking) { _, newValue in
            // Synchronize local state with parent state
            if !newValue && isSpeakingThis {
                // Parent says we're not speaking anymore, clear local state
                isSpeakingThis = false
            }
        }
    }

    // MARK: - TTS Methods

    private func handleSpeak() {
        // Notify parent to stop other audio and set this as current speaking segment
        onSpeak()

        guard let targetLanguage = isOriginal ? englishLanguage : selectedLanguage else {
            print("❌ No target language available for TTS. isOriginal: \(isOriginal), englishLanguage: \(englishLanguage?.name ?? "nil"), selectedLanguage: \(selectedLanguage?.name ?? "nil")")
            return
        }

        // Update local and parent state immediately
        isSpeakingThis = true
        onUpdateSpeakingState(segment.id)

        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        print("🗣️ Speaking text: '\(segment.text)' in language: \(targetLanguage.name) (\(targetLanguage.languageCode)) with TTS: \(targetLanguage.googleTTSLanguageCode ?? "fallback") / \(targetLanguage.googleTTSVoice ?? "fallback")")

        // Speak with completion callback to properly clear state
        ttsManager.speak(text: segment.text, language: targetLanguage) { success in
            DispatchQueue.main.async {
                // Clear speaking state
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
            onChangeLanguageRequest: { }
        )
    }
}
