import SwiftUI
import AVFoundation
import CoreMedia
import UIKit

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
    
    // Ad tracking state
    @State private var summaryGenerationCount = 0
    @State private var translationAttemptCount = 0
    
    // Toast state for copy functionality
    @State private var showToast = false
    @State private var toastMessage = ""
    
    // Audio player state
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying: Bool = false
    @State private var playbackTime: TimeInterval = 0
    @State private var audioPlayerDelegate = AudioPlayerDelegate()
    @State private var isSeeking = false
    @State private var seekTime: TimeInterval = 0
    private let playbackTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    @StateObject private var languageManager = LanguageManager()

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                // iPad centered layout
                GeometryReader { geometry in
                    HStack {
                        Spacer()
                        
                        VStack(spacing: 0) {
                            // Action buttons header
                            actionButtonsView
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemGroupedBackground))
                                .opacity(animateButtons ? 1 : 0)
                                .offset(y: animateButtons ? 0 : -10)
                                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: animateButtons)
                            
                            // Content area
                            contentView
                        }
                        .frame(maxWidth: min(geometry.size.width * 0.8, 1000))
                        
                        Spacer()
                    }
                }
            } else {
                // iPhone layout
                VStack(spacing: 0) {
                    // Action buttons header
                    actionButtonsView
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemGroupedBackground))
                        .opacity(animateButtons ? 1 : 0)
                        .offset(y: animateButtons ? 0 : -10)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: animateButtons)
                    
                    // Content area
                    contentView
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
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToLanguageSelection) {
            LanguageSelectionView(selectedLanguage: selectedTargetLanguage) { language in
                selectedTargetLanguage = language
                
                // Reset navigation state and handle translation
                Task { @MainActor in
                    navigateToLanguageSelection = false
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
                SummaryView(summary: summary, sessionDuration: getActualDuration(), sessionTitle: recording?.title ?? session.title) { timestamp in
                    seekToTimestamp(timestamp)
                }
            } else {
                EmptyView()
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
                onChangeLanguageRequest: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.handleChangeLanguageRequestFromTranslation()
                    }
                }
            )
            .onDisappear {
                // Clean up navigation state when returning from translation view
                Task { @MainActor in
                    navigateToTranslation = false
                }
            }
        }

        .alert("Error", isPresented: $showingError) {
            Button("OK") { 
                // Clear error state when dismissed
                errorMessage = nil
            }
            if errorMessage?.contains("cancelled") == true {
                Button("Retry") {
                    errorMessage = nil
                    Task {
                        await generateSummary()
                    }
                }
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .onAppear {
            withAnimation {
                animateButtons = true
            }
            generateHapticFeedback(.light)
        }
        .onDisappear {
            stopAudio()
        }
        .onReceive(playbackTimer) { _ in
            if let player = audioPlayer, isPlaying, !isSeeking {
                playbackTime = player.currentTime
                
                // Update current playing timestamp for UI highlighting
                currentPlayingTimestamp = player.currentTime
                
                // Check if playback finished
                if player.currentTime >= player.duration {
                    stopAudio()
                }
            }
        }
    }
    

    
    // MARK: - Action Buttons
    
    private var actionButtonsView: some View {
        HStack(spacing: 12) {
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
            .frame(maxWidth: .infinity) // Expand to fill available space
            
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
            .frame(maxWidth: .infinity) // Expand to fill available space
        }
        .frame(maxWidth: .infinity) // Ensure container uses full width
    }
    
    // MARK: - Content Views
    
    @ViewBuilder
    private var contentView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 16) {
                // Session stats header
                sessionStatsView
                
                // Notes section (if available)
                if let recording = recording, let notes = recording.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    notesView(notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                
                if let transcript = session.transcript, !transcript.isEmpty {
                    TranscriptSegmentsList(
                        segments: transcript,
                        currentPlayingTimestamp: currentPlayingTimestamp,
                        onSeekToTimestamp: seekToTimestamp,
                        onCopyText: copyTextToClipboard
                    )
                } else {
                    emptyTranscriptView
                }
            }
            .padding(UIDevice.current.userInterfaceIdiom == .pad ? 24 : 16)
        }
        .refreshable {
            await handleRefresh()
        }
    }
    
    private func notesView(notes: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "note.text")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                
                Text("Notes")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    copyTextToClipboard(notes)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            
            Text(notes)
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
        }
        .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 0 : 0)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 0 : 0)
    }
    
    private var sessionStatsView: some View {
        VStack(spacing: 16) {
            // Session info
            VStack(spacing: 8) {
                HStack {
                    Text("Duration")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatDuration(getActualDuration()))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                }
                
                if let transcript = session.transcript {
                    HStack {
                        Text("Segments")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(transcript.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                    }
                }
                
                HStack {
                    Text("Language")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(displayLanguage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                }
            }
            
            // Audio playback controls
            if isPlaying {
                audioPlaybackControls
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
    
    private var actualDurationForProgress: TimeInterval {
        let duration = getActualDuration()
        return max(0.1, duration) // Minimum 0.1 to avoid division by zero
    }
    
    private var clampedPlaybackTime: TimeInterval {
        let actualDuration = actualDurationForProgress
        return max(0, min(playbackTime, actualDuration))
    }
    
    private var audioPlaybackControls: some View {
        HStack(spacing: 12) {
            Button(action: stopAudio) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.red)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Now Playing")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.primary)
                    Spacer()
                    HStack(spacing: 4) {
                        Text(formatDuration(isSeeking ? seekTime : clampedPlaybackTime))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(isSeeking ? .blue : .secondary)
                        Text("/")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatDuration(actualDurationForProgress))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
                
                // Interactive seek slider
                Slider(
                    value: Binding(
                        get: { 
                            let currentValue = isSeeking ? seekTime : clampedPlaybackTime
                            return currentValue
                        },
                        set: { newValue in
                            isSeeking = true
                            seekTime = newValue
                        }
                    ),
                    in: 0...actualDurationForProgress,
                    onEditingChanged: { isEditing in
                        if isEditing {
                            // User started seeking
                            isSeeking = true
                        } else {
                            // User finished seeking
                            seekToTime(seekTime)
                            isSeeking = false
                        }
                    }
                )
                .accentColor(.blue)
                .allowsHitTesting(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }
    
    private var displayLanguage: String {
        if session.languageCode.hasPrefix("en") {
            return "English"
        } else if session.languageCode.hasPrefix("es") {
            return "Spanish"
        } else if session.languageCode.hasPrefix("fr") {
            return "French"
        } else {
            return session.languageCode.uppercased()
        }
    }
    
    private func getActualDuration() -> TimeInterval {
        // Try session duration first
        if session.duration > 0 {
            return session.duration
        }
        
        // Try recording duration as fallback
        if let recording = recording, recording.duration > 0 {
            return recording.duration
        }
        
        // Try to get duration from audio file directly (synchronous)
        let asset = AVAsset(url: session.audioURL)
        let duration = asset.duration
        let timeInterval = CMTimeGetSeconds(duration)
        if timeInterval > 0 && !timeInterval.isNaN && timeInterval.isFinite {
            return timeInterval
        }
        
        // If all else fails, return 0
        return 0
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration <= 0 {
            return "Unknown"
        }
        
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
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
    
    // MARK: - Copy Functionality
    
    private func copyTextToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        toastMessage = "Text copied"
        generateHapticFeedback(.medium)
        
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
        
        // Ensure we're on main thread for navigation
        Task { @MainActor in
            if hasTranslation {
                navigateToTranslation = true
            } else {
                navigateToLanguageSelection = true
            }
        }
    }
    
    private func generatingSummaryPostOtherProcess(_ segments: [TranscriptSegment]) async {
        isGeneratingSummary = true
        generateHapticFeedback(.light)
        
        do {
            let summary = try await di.summarization.summarize(segments: segments, locale: session.languageCode, title: session.title, notes: recording?.notes)
            
            generatedSummary = summary
            
            // Cache the summary in the Recording if available
            if let recording = recording {
                recording.cacheSummary(summary, language: session.languageCode)
                try? modelContext.save()
            }
            
            // Reset force regenerate flag
            forceRegenerateSummary = false
            
            generateHapticFeedback(.success)
            navigateToSummary = true
        } catch {
            // Check if it's a URL cancellation error
            if let urlError = error as? URLError, urlError.code == .cancelled {
                showError("Request was cancelled. Please try again.")
            } else {
                showError("Failed to generate summary: \(error.localizedDescription)")
            }
            generateHapticFeedback(.error)
        }
        
        isGeneratingSummary = false
    }
    
    @MainActor
    private func generateSummary() async {
        guard let segments = session.transcript, !segments.isEmpty else {
            showError("No transcript available to summarize")
            return
        }
        
        summaryGenerationCount += 1
        
        // Randomly show ad for summary generation (1 in 3 chance after 2nd attempt)
        if summaryGenerationCount >= 2 && Int.random(in: 1...3) == 1, di.adManager.isAdReady, let rootVC = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController {
            di.adManager.presentInterstitial(from: rootVC) { _ in
                Task {
                    await self.generatingSummaryPostOtherProcess(segments)
                }
            }
        } else {
            await self.generatingSummaryPostOtherProcess(segments)
        }

    }
    
    private func translateTranscriptPostOtherProcess(_ segments: [TranscriptSegment], _ targetLanguage: String) async {
        isTranslating = true
        generateHapticFeedback(.light)
        
        do {
            let translated = try await di.translation.translate(segments: segments, targetLanguage: targetLanguage)
            
            // Update state on main thread
            await MainActor.run {
                translatedTranscript = translated
                generateHapticFeedback(.success)
                
                // Navigate to translation view after successful translation
                navigateToTranslation = true
            }
        } catch {
            var errorMessage = "Failed to translate"
            if let urlError = error as? URLError, urlError.code == .timedOut {
                errorMessage = "Translation service is experiencing delays. The text has been automatically split into smaller chunks, but some parts may still timeout. Please check your network connection."
            } else {
                errorMessage = "Failed to translate: \(error.localizedDescription)"
            }
            showError(errorMessage)
            generateHapticFeedback(.error)
        }
        
        isTranslating = false
    }
    
    @MainActor
    private func translateTranscript(to targetLanguage: String) async {
        guard let segments = session.transcript, !segments.isEmpty else {
            showError("No transcript available to translate")
            return
        }
        
        translationAttemptCount += 1
        
        // Randomly show ad for translation (1 in 3 chance after 2nd attempt)
        if translationAttemptCount >= 2 && Int.random(in: 1...3) == 1, di.adManager.isAdReady, let rootVC = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController {
            di.adManager.presentInterstitial(from: rootVC) { _ in
                Task {
                    await self.translateTranscriptPostOtherProcess(segments, targetLanguage)
                }
            }
        } else {
            await self.translateTranscriptPostOtherProcess(segments, targetLanguage)
        }

    }
    
    @MainActor
    private func translateTranscriptForLanguageChange(to targetLanguage: String) async -> [TranscriptSegment]? {
        guard let segments = session.transcript, !segments.isEmpty else {
            return nil
        }
        
        do {
            let translated = try await di.translation.translate(segments: segments, targetLanguage: targetLanguage)
            
            // Update the stored translation for this view
            translatedTranscript = translated
            
            return translated
        } catch {
            if let urlError = error as? URLError, urlError.code == .timedOut {
            } else {
            }
            return nil
        }
    }
    
    @MainActor
    private func handleChangeLanguageRequestFromTranslation() {
        
        // Ensure we're back to this view
        navigateToTranslation = false
        
        // Add haptic feedback
        generateHapticFeedback(.medium)
        
        // Open language selection (same as original translate flow)
        navigateToLanguageSelection = true
    }
    

    
    private func seekToTimestamp(_ timestamp: TimeInterval) {
        currentPlayingTimestamp = timestamp
        generateHapticFeedback(.light)
        
        // Setup and play audio from timestamp
        setupAudioPlayer()
        
        // Seek to timestamp and play
        if let player = audioPlayer {
            player.currentTime = timestamp
            if !isPlaying {
                playAudio()
            }
        }
    }
    
    private func seekToTime(_ time: TimeInterval) {
        guard let player = audioPlayer else { 
            return 
        }
        
        let clampedTime = max(0, min(time, player.duration))
        
        player.currentTime = clampedTime
        playbackTime = clampedTime
        currentPlayingTimestamp = clampedTime
        
        generateHapticFeedback(.light)
    }
    
    private func setupAudioPlayer() {
        guard audioPlayer == nil else { return }
        
        do {
            let audioURL = session.audioURL
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer?.delegate = audioPlayerDelegate
            audioPlayer?.prepareToPlay()
            
            // Set up delegate callback
            audioPlayerDelegate.onFinish = {
                DispatchQueue.main.async {
                    self.stopAudio()
                }
            }
        } catch {
        }
    }
    
    private func playAudio() {
        guard let player = audioPlayer else { return }
        
        // Set up audio session for playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            if player.play() {
                isPlaying = true
            }
        } catch {
        }
    }
    
    private func stopAudio() {
        audioPlayer?.stop()
        isPlaying = false
        currentPlayingTimestamp = nil
        isSeeking = false
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)
    }
    
    @MainActor
    private func handleRefresh() async {
        guard hasSummary else { return }
        
        isRefreshing = true
        generateHapticFeedback(.light)
        
        // Clear any previous errors
        errorMessage = nil
        showingError = false
        
        // Clear cached summary to force regeneration
        recording?.clearCachedSummary()
        try? modelContext.save()
        
        // Set flag to force regeneration
        forceRegenerateSummary = true
        generatedSummary = nil
        
        
        // Create an independent task for summary generation to avoid cancellation
        // when pull-to-refresh gesture completes
        Task.detached {
            await self.generateSummaryDetached()
        }
        
        isRefreshing = false
    }
    
    private func generateSummaryDetached() async {
        // Capture needed values since we can't access @State properties from detached task
        guard let segments = session.transcript, !segments.isEmpty else {
            await MainActor.run {
                showError("No transcript available to summarize")
            }
            return
        }
        
        let locale = session.languageCode
        
        await MainActor.run {
            isGeneratingSummary = true
            generateHapticFeedback(.light)
        }
        
        do {
            let summary = try await di.summarization.summarize(segments: segments, locale: locale, title: session.title, notes: recording?.notes)
            
            await MainActor.run {
                generatedSummary = summary
                
                // Cache the summary in the Recording if available
                if let recording = recording {
                    recording.cacheSummary(summary, language: locale)
                    try? modelContext.save()
                }
                
                // Reset force regenerate flag
                forceRegenerateSummary = false
                
                generateHapticFeedback(.success)
                navigateToSummary = true
                isGeneratingSummary = false
            }
        } catch {
            await MainActor.run {
                // Check if it's a URL cancellation error
                if let urlError = error as? URLError, urlError.code == .cancelled {
                    showError("Request was cancelled. Please try again.")
                } else {
                    showError("Failed to generate summary: \(error.localizedDescription)")
                }
                generateHapticFeedback(.error)
                isGeneratingSummary = false
            }
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
        
        // Auto-dismiss error after 5 seconds if it's not a critical error
        if !message.lowercased().contains("api key") && !message.lowercased().contains("authentication") {
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                if errorMessage == message { // Only dismiss if it's still the same error
                    DispatchQueue.main.async {
                        self.showingError = false
                        self.errorMessage = nil
                    }
                }
            }
        }
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
    
    @State private var isPressed = false
    
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
            .frame(maxWidth: .infinity, minHeight: 56) // Full width and proper touch target
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemGroupedBackground))
                    .opacity(isPressed ? 0.7 : 1.0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(isPressed ? 0.4 : 0.2), lineWidth: isPressed ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12)) // Make entire area clickable
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed || isLoading ? 0.98 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isLoading)
        .disabled(isLoading)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        } perform: {}
    }
}

struct TranscriptSegmentsList: View {
    let segments: [TranscriptSegment]
    let currentPlayingTimestamp: TimeInterval?
    let onSeekToTimestamp: (TimeInterval) -> Void
    let onCopyText: (String) -> Void
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(segments) { segment in
                TranscriptSegmentRow(
                    segment: segment,
                    isCurrentlyPlaying: isSegmentCurrentlyPlaying(segment),
                    onSeekToTimestamp: onSeekToTimestamp,
                    onCopyText: onCopyText
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
    let onCopyText: (String) -> Void
    
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
                    .onLongPressGesture {
                        onCopyText(segment.text)
                    }
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
