import SwiftUI

struct TranscriptResultView: View {
    let session: Session
    let recording: Recording? // Optional Recording for caching
    @EnvironmentObject private var di: ServiceContainer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var isGeneratingSummary = false
    @State private var isTranslating = false
    @State private var navigateToSummary = false
    @State private var navigateToTranslation = false

    @State private var generatedSummary: Summary?
    @State private var translatedTranscript: [TranscriptSegment]?
    @State private var selectedTargetLanguage: Language?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var animateButtons = false
    @State private var currentPlayingTimestamp: TimeInterval?
    @State private var isRefreshing = false
    @State private var forceRegenerateSummary = false
    @State private var navigateToLanguageSelection = false
    
    @StateObject private var languageManager = LanguageManager()

    var body: some View {
        VStack(spacing: 0) {
            // Action buttons header
            actionButtonsView
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .opacity(animateButtons ? 1 : 0)
                .offset(y: animateButtons ? 0 : -10)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: animateButtons)
            
            // Content area
            contentView
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToLanguageSelection) {
            LanguageSelectionView(selectedLanguage: selectedTargetLanguage) { language in
                selectedTargetLanguage = language
                // Reset navigation state immediately to prevent navigation issues
                navigateToLanguageSelection = false
                Task {
                    await translateTranscript(to: language.name)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: transcriptText,
                    preview: SharePreview("Transcript - \(session.title)", image: Image(systemName: "doc.text"))
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                }
                .onTapGesture {
                    generateHapticFeedback(.medium)
                }
            }
        }
        .navigationDestination(isPresented: $navigateToSummary) {
            if let summary = generatedSummary {
                SummaryView(summary: summary) { timestamp in
                    seekToTimestamp(timestamp)
                }
            }
        }
        .navigationDestination(isPresented: $navigateToTranslation) {
            TranslationView(
                originalTranscript: session.transcript ?? [],
                translatedTranscript: translatedTranscript ?? [],
                targetLanguage: selectedTargetLanguage,
                onSeekToTimestamp: { timestamp in
                    seekToTimestamp(timestamp)
                },
                onLanguageChange: { newLanguage in
                    return await translateTranscriptForLanguageChange(to: newLanguage.name)
                }
            )
        }

        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .onAppear {
            withAnimation {
                animateButtons = true
            }
            generateHapticFeedback(.light)
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtonsView: some View {
        HStack(spacing: 8) {
            // AI Summary Button
            ActionButton(
                title: "AI Summary",
                subtitle: hasSummary ? "View" : "Generate",
                icon: "brain.head.profile",
                color: .purple,
                isLoading: isGeneratingSummary,
                loadingText: "Analyzing...",
                action: handleSummaryAction
            )
            
            // Translate Button  
            ActionButton(
                title: "Translate",
                subtitle: hasTranslation ? "View" : "Generate",
                icon: "globe",
                color: .blue,
                isLoading: isTranslating,
                loadingText: "Translating...",
                action: handleTranslateAction
            )
        }
    }
    
    // MARK: - Content Views
    
    @ViewBuilder
    private var contentView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 16) {
                if let transcript = session.transcript, !transcript.isEmpty {
                    TranscriptSegmentsList(
                        segments: transcript,
                        currentPlayingTimestamp: currentPlayingTimestamp,
                        onSeekToTimestamp: seekToTimestamp
                    )
                } else {
                    emptyTranscriptView
                }
            }
            .padding()
        }
        .refreshable {
            await handleRefresh()
        }
    }
    
    private var emptyTranscriptView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.secondary)
            
            Text("No Transcript Available")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("The transcript is not yet available for this session.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }
    
    // MARK: - Helper Properties
    
    private var transcriptText: String {
        guard let segments = session.transcript else { return "" }
        return segments.map { segment in
            let speaker = segment.speaker.map { "\($0): " } ?? ""
            return "\(speaker)\(segment.text)"
        }.joined(separator: "\n\n")
    }
    
    private var hasSummary: Bool {
        recording?.hasSummary == true || session.summary != nil || generatedSummary != nil
    }
    
    private var hasTranslation: Bool {
        translatedTranscript != nil
    }
    
    // MARK: - Actions
    
    private func handleSummaryAction() {
        generateHapticFeedback(.medium)
        
        // Check cached summary first (Recording cache -> Session -> Generated)
        if let cachedSummary = recording?.getCachedSummary(), !forceRegenerateSummary {
            print("📋 Using cached summary from Recording")
            generatedSummary = cachedSummary
            navigateToSummary = true
        } else if let existingSummary = session.summary ?? generatedSummary {
            generatedSummary = existingSummary
            navigateToSummary = true
        } else {
            Task {
                await generateSummary()
            }
        }
    }
    
    private func handleTranslateAction() {
        generateHapticFeedback(.medium)
        
        if hasTranslation {
            navigateToTranslation = true
        } else {
            navigateToLanguageSelection = true
        }
    }
    
    @MainActor
    private func generateSummary() async {
        guard let segments = session.transcript, !segments.isEmpty else {
            showError("No transcript available to summarize")
            return
        }
        
        isGeneratingSummary = true
        generateHapticFeedback(.light)
        
        do {
            print("🌐 Generating new summary from API")
            let summary = try await di.summarization.summarize(segments: segments, locale: session.languageCode)
            generatedSummary = summary
            
            // Cache the summary in the Recording if available
            if let recording = recording {
                recording.cacheSummary(summary, language: session.languageCode)
                try? modelContext.save()
                print("💾 Cached summary in Recording")
            }
            
            // Reset force regenerate flag
            forceRegenerateSummary = false
            
            generateHapticFeedback(.success)
            navigateToSummary = true
        } catch {
            showError("Failed to generate summary: \(error.localizedDescription)")
            generateHapticFeedback(.error)
        }
        
        isGeneratingSummary = false
    }
    
    @MainActor
    private func translateTranscript(to targetLanguage: String) async {
        guard let segments = session.transcript, !segments.isEmpty else {
            showError("No transcript available to translate")
            return
        }
        
        isTranslating = true
        generateHapticFeedback(.light)
        
        do {
            let translated = try await di.translation.translate(segments: segments, targetLanguage: targetLanguage)
            translatedTranscript = translated
            
            generateHapticFeedback(.success)
            
            // Open translation view after successful translation
            navigateToTranslation = true
        } catch {
            showError("Failed to translate: \(error.localizedDescription)")
            generateHapticFeedback(.error)
        }
        
        isTranslating = false
    }
    
    @MainActor
    private func translateTranscriptForLanguageChange(to targetLanguage: String) async -> [TranscriptSegment]? {
        guard let segments = session.transcript, !segments.isEmpty else {
            print("❌ No transcript available to translate")
            return nil
        }
        
        do {
            let translated = try await di.translation.translate(segments: segments, targetLanguage: targetLanguage)
            
            // Update the stored translation for this view
            translatedTranscript = translated
            
            print("✅ Language change translation completed for: \(targetLanguage)")
            return translated
        } catch {
            print("❌ Failed to translate for language change: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func seekToTimestamp(_ timestamp: TimeInterval) {
        currentPlayingTimestamp = timestamp
        generateHapticFeedback(.light)
        
        // TODO: Integrate with audio player to seek to timestamp
        print("Seeking to timestamp: \(timestamp)")
    }
    
    @MainActor
    private func handleRefresh() async {
        guard hasSummary else { return }
        
        isRefreshing = true
        generateHapticFeedback(.light)
        
        // Clear cached summary to force regeneration
        recording?.clearCachedSummary()
        try? modelContext.save()
        
        // Set flag to force regeneration
        forceRegenerateSummary = true
        generatedSummary = nil
        
        print("🔄 Pull-to-refresh: Regenerating summary")
        
        // Generate new summary
        await generateSummary()
        
        isRefreshing = false
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

// MARK: - Supporting Views

struct ActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let isLoading: Bool
    let loadingText: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.9)
                            .progressViewStyle(CircularProgressViewStyle(tint: color))
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(color)
                    }
                }
                .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(isLoading ? loadingText : title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    if !isLoading {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                
                Spacer()
                
                if !isLoading {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isLoading ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isLoading)
        .disabled(isLoading)
    }
}

struct TranscriptSegmentsList: View {
    let segments: [TranscriptSegment]
    let currentPlayingTimestamp: TimeInterval?
    let onSeekToTimestamp: (TimeInterval) -> Void
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(segments) { segment in
                TranscriptSegmentRow(
                    segment: segment,
                    isCurrentlyPlaying: isSegmentCurrentlyPlaying(segment),
                    onSeekToTimestamp: onSeekToTimestamp
                )
            }
        }
    }
    
    private func isSegmentCurrentlyPlaying(_ segment: TranscriptSegment) -> Bool {
        guard let currentTime = currentPlayingTimestamp else { return false }
        return currentTime >= segment.startTime && currentTime <= segment.endTime
    }
}

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    let isCurrentlyPlaying: Bool
    let onSeekToTimestamp: (TimeInterval) -> Void
    
    var body: some View {
        Button(action: {
            onSeekToTimestamp(segment.startTime)
        }) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    Text(segment.startTime.formattedMS())
                        .font(.caption2.weight(.medium))
                        .foregroundColor(isCurrentlyPlaying ? .blue : .secondary)
                    
                    if let speaker = segment.speaker {
                        Text(speaker)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 60)
                
                Text(segment.text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isCurrentlyPlaying ? Color.blue.opacity(0.1) : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isCurrentlyPlaying ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}



// MARK: - Extensions

private extension UIImpactFeedbackGenerator.FeedbackStyle {
    static let success = UIImpactFeedbackGenerator.FeedbackStyle.light
    static let error = UIImpactFeedbackGenerator.FeedbackStyle.heavy
}


// MARK: - Preview

#Preview {
    let sampleSegments = [
        TranscriptSegment(
            id: UUID(),
            speaker: "John",
            text: "Welcome everyone to today's meeting. Let's start by reviewing our progress on the current project.",
            startTime: 0,
            endTime: 5
        ),
        TranscriptSegment(
            id: UUID(),
            speaker: "Sarah",
            text: "Thanks John. I've completed the user interface designs and they're ready for review.",
            startTime: 5,
            endTime: 10
        ),
        TranscriptSegment(
            id: UUID(),
            speaker: "Mike",
            text: "Great work Sarah. I'll review those designs this afternoon and provide feedback by tomorrow.",
            startTime: 10,
            endTime: 15
        )
    ]
    
    let sampleSession = Session(
        id: UUID(),
        title: "Team Meeting - Project Review",
        createdAt: Date(),
        audioURL: URL(string: "file://sample.m4a")!,
        duration: 1800,
        languageCode: "en-US",
        transcript: sampleSegments
    )
    
    TranscriptResultView(session: sampleSession, recording: nil)
        .environmentObject(ServiceContainer.create())
}
