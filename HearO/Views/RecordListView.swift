import SwiftUI
import AVFoundation
import SwiftData
import UIKit

extension Notification.Name {
    static let didSaveRecording = Notification.Name("didSaveRecording")
}

final class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish?() }
}

struct RecordListView: View {
    @EnvironmentObject var di: ServiceContainer
    @Environment(\.modelContext) private var modelContext
    @Binding var showRecordingSheet: Bool

    @State private var recordings: [Recording] = []
    @State private var isLoading = true

    // Playback state
    @State private var player: AVAudioPlayer?
    @State private var playingID: UUID?
    @State private var isPlaying: Bool = false
    @State private var playerDelegate = AudioPlayerDelegate()
    @State private var playbackTime: TimeInterval = 0
    private let playbackTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    // Mini recorder state
    @State private var recElapsed: TimeInterval = 0
    @State private var showMiniSavePrompt = false
    @State private var miniNameText: String = ""
    @State private var miniLastDuration: TimeInterval = 0
    @State private var miniCollapsed: Bool = false
    @State private var miniURL: URL? = nil // capture URL before stop

    // Transcription state (pre-recorded)
    @State private var isTranscribing: Bool = false
    @State private var transcribingRecordingID: UUID? = nil
    @State private var transcribeError: String? = nil
    @State private var transcriptText: String = ""
    @State private var transcriptSegments: [TranscriptSegment] = []
    @State private var currentTranscriptSession: Session?
    @State private var currentTranscriptRecording: Recording?
    @State private var navigateToTranscript: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 12) {
                    // Lightweight header so the screen never looks empty
                    if isLoading {
                        ProgressView().padding()
                    } else {
                        recordList
                    }
                }

                // Pre-recorded transcription progress
                if isTranscribing {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Transcribing…").font(.footnote).foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 0.5))
                    }
                }
            }
            .onAppear {
                Task { await loadRecordings() }
                playerDelegate.onFinish = {
                    isPlaying = false
                    playingID = nil
                    playbackTime = 0
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                
                // Ensure any recording session is properly cleaned up
                if !di.audio.isRecording {
                    di.audio.deactivateSessionIfNeeded()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .didSaveRecording)) { _ in
                Task { await loadRecordings() }
            }
            .onReceive(playbackTimer) { _ in
                if isPlaying, let player, playingID != nil { playbackTime = player.currentTime }
                if di.audio.isSessionActive {
                    if di.audio.isRecording { di.audio.updateMeters() }
                    recElapsed = di.audio.currentTime
                }
            }
            // New: when sheet is dismissed by swipe, refresh state so mini bar shows immediately
            .onChange(of: showRecordingSheet) { oldValue, newValue in
                if oldValue == true && newValue == false, di.audio.isSessionActive {
                    // bump a state change to trigger view update and show mini bar
                    recElapsed = di.audio.currentTime
                }
            }
            .overlay(alignment: .bottom) {
                if di.audio.isSessionActive { miniBar.padding(.horizontal) }
            }
            .alert("Name your recording", isPresented: $showMiniSavePrompt) {
                TextField("Enter a title", text: $miniNameText)
                Button("Save") { saveMiniRecording() }
                Button("Cancel", role: .cancel) { showMiniSavePrompt = false }
            }
            .alert("Transcription Error", isPresented: .constant(transcribeError != nil)) {
                Button("OK", role: .cancel) { transcribeError = nil }
            } message: {
                Text(transcribeError ?? "")
            }
            .navigationDestination(isPresented: $navigateToTranscript) {
                if let session = currentTranscriptSession, let recording = currentTranscriptRecording {
                    TranscriptResultView(session: session, recording: recording)
                } else {
                    Text("No transcript available")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    // MARK: - Record List

    private var recordList: some View {
        List {
            ForEach(recordings) { rec in
                // Compute per-row playback state and total duration source
                let isRowPlaying = (playingID == rec.id && isPlaying)
                let totalDuration: TimeInterval = (isRowPlaying ? (player?.duration ?? rec.duration) : rec.duration)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(action: { togglePlayback(for: rec) }) {
                            Image(systemName: isRowPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                                .contentTransition(.symbolEffect(.replace))
                        }.padding(.horizontal, 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rec.title).font(.body)
                            Text(rec.createdAt, style: .date) + Text(", ") + Text(rec.createdAt, style: .time)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        // Quick action button to transcribe or view transcript
                        Button(action: { Task { await transcribeRecording(rec) } }) {
                            HStack(spacing: 4) {
                                if transcribingRecordingID == rec.id {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: rec.hasTranscript ? "text.bubble.fill" : "text.bubble")
                                        .foregroundColor(rec.hasTranscript ? .green : .accentColor)
                                }
                                
                                if transcribingRecordingID == rec.id {
                                    Text("Loading...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else if rec.hasTranscript {
                                    Text("View")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Text("Transcribe")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isTranscribing)
                        .opacity(isTranscribing ? 0.5 : 1.0)
                    }
                    if playingID == rec.id {
                        HStack(spacing: 8) {
                            Text(format(duration: playbackTime))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                            Slider(value: Binding(
                                get: { min(playbackTime, totalDuration) },
                                set: { newVal in
                                    let clamped = max(0, min(newVal, totalDuration))
                                    playbackTime = clamped
                                    if let player = player { player.currentTime = clamped }
                                }
                            ), in: 0...max(0.1, totalDuration))
                            Text(format(duration: totalDuration))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listRowSeparator(.visible)
            }
            .onDelete(perform: delete)
        }
        .listStyle(.insetGrouped)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: recordings)
        .animation(.easeInOut(duration: 0.2), value: playingID)
        .animation(.easeInOut(duration: 0.2), value: isPlaying)
        .overlay {
            if !isLoading && recordings.isEmpty {
                ContentUnavailableView {
                    Label("No recordings yet", systemImage: "waveform")
                } description: {
                    Text("Tap Start Recording to create your first clip.")
                } actions: {
                    Button("Start Recording") { showRecordingSheet = true }
                }
                .padding()
            }
        }
    }

    // MARK: - Transcription (pre-recorded)
    @MainActor
    private func transcribeRecording(_ rec: Recording) async {
        isTranscribing = true
        transcribingRecordingID = rec.id
        transcribeError = nil
        transcriptText = ""
        transcriptSegments = []
        currentTranscriptSession = nil
        currentTranscriptRecording = nil
        defer { 
            isTranscribing = false
            transcribingRecordingID = nil
        }
        
        do {
            let segments: [TranscriptSegment]
            let languageCode = "en"
            
            // Check if transcript is already cached
            if rec.hasTranscript, let cachedSegments = rec.getCachedTranscriptSegments() {
                print("📋 Using cached transcript for recording: \(rec.title)")
                segments = cachedSegments
            } else {
                print("🌐 Fetching transcript from API for recording: \(rec.title)")
                segments = try await di.transcription.transcribe(audioURL: rec.finalAudioURL(), languageCode: languageCode)
                
                // Cache the transcript in the Recording model
                rec.cacheTranscript(segments: segments, language: languageCode)
                
                // Save to persistent storage
                try modelContext.save()
                
                print("💾 Cached transcript for recording: \(rec.title)")
            }
            
            transcriptText = segments.map { $0.text }.joined(separator: "\n")
            transcriptSegments = segments
            
            // Create a temporary Session object for the transcript view
            currentTranscriptSession = Session(
                id: rec.id,
                title: rec.title,
                createdAt: rec.createdAt,
                audioURL: rec.finalAudioURL(),
                duration: rec.duration,
                languageCode: languageCode,
                transcript: segments,
                highlights: nil,
                summary: nil
            )
            
            // Store the recording reference for caching
            currentTranscriptRecording = rec
            
            // Pause any playing audio before navigating
            if let player = player, isPlaying {
                player.pause()
                isPlaying = false
                setPlaybackSessionActive(false)
            }
            
            navigateToTranscript = true
        } catch {
            transcribeError = error.localizedDescription
        }
    }

    // MARK: - Mini Recorder (Bottom)
    private var miniBar: some View {
        HStack(spacing: 12) {
            // Collapse/expand affordance
            Button(action: { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { miniCollapsed.toggle() } }) {
                Image(systemName: miniCollapsed ? "chevron.up" : "chevron.down")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color(.tertiarySystemFill)))
            }

            if miniCollapsed == false {
                // Left tappable area re-opens full RecordingView
                Button(action: { showRecordingSheet = true }) {
                    HStack(spacing: 12) {
                        Circle().fill(di.audio.isRecording ? Color.red : Color.orange)
                            .frame(width: 10, height: 10)
                            .opacity(di.audio.isRecording ? 1 : 0.6)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: di.audio.isRecording)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(di.audio.isRecording ? "Recording…" : "Paused")
                                .font(.footnote).foregroundColor(.secondary)
                            Text(format(duration: recElapsed))
                                .font(.headline.monospacedDigit())
                        }
                        // Tiny reactive bar
                        Rectangle()
                            .fill(LinearGradient(colors: [.red, .orange], startPoint: .bottom, endPoint: .top))
                            .frame(width: 24, height: max(8, CGFloat(max(0, (di.audio.currentPower + 60) / 60)) * 24))
                            .cornerRadius(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else {
                // Collapsed compact clock view
                Button(action: { showRecordingSheet = true }) {
                    Text(format(duration: recElapsed))
                        .font(.headline.monospacedDigit())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            // Pause/Resume or Stop prompt
            Button(action: toggleMiniPauseResume) {
                Image(systemName: di.audio.isRecording ? "pause.fill" : "play.fill")
                    .font(.headline)
                    .contentTransition(.symbolEffect(.replace))
            }
            Button(role: .destructive, action: stopMiniAndPrompt) {
                Image(systemName: "stop.fill").font(.headline).foregroundColor(.red)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [Color(.secondarySystemBackground), Color(.systemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator), lineWidth: 0.5))
    }

    // MARK: - Actions
    private func toggleMiniPauseResume() {
        do {
            if di.audio.isRecording {
                // Pause only
                try di.audio.pauseRecording()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } else if di.audio.isSessionActive {
                // Resume if we still have a session
                try di.audio.resumeRecording()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } else {
                // No session -> open full recorder
                showRecordingSheet = true
            }
        } catch { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    }

    private func stopMiniAndPrompt() {
        do {
            // Capture URL before stopping, because stop clears the recorder
            miniURL = di.audio.currentRecordingURL
            miniLastDuration = try di.audio.stopRecording()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showMiniSavePrompt = true
        } catch { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    }

    private func saveMiniRecording() {
        guard let url = miniURL else { return }
        let filename = url.deletingPathExtension().lastPathComponent
        let id = UUID(uuidString: filename) ?? UUID()
        let title = miniNameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ("Session " + Date.now.formatted(date: .abbreviated, time: .shortened)) : miniNameText
        // Store relative path so sandbox container UUID changes don't break playback
        let relativePath = "audio/\(id.uuidString).m4a"
        let rec = Recording(id: id, title: title, createdAt: Date(), audioURL: relativePath, duration: miniLastDuration)
        do {
            try RecordingDataStore(context: modelContext).saveRecording(rec)
            NotificationCenter.default.post(name: .didSaveRecording, object: nil)
            miniNameText = ""; showMiniSavePrompt = false; miniURL = nil
        } catch { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    }

    @MainActor
    private func loadRecordings() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try RecordingDataStore(context: modelContext).fetchRecordings()
            recordings = fetched
        } catch {
            // Keep list empty on error; optionally log
        }
    }

    private func togglePlayback(for rec: Recording) {
        do {
            if playingID == rec.id, let player = player {
                if isPlaying {
                    player.pause()
                    isPlaying = false
                    setPlaybackSessionActive(false)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } else {
                    setPlaybackSessionActive(true)
                    player.play()
                    isPlaying = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } else {
                // Stop any current player and reset state immediately
                player?.stop()
                player = nil
                isPlaying = false
                playingID = nil
                playbackTime = 0
                
                // Setup new player asynchronously to avoid blocking UI
                Task { @MainActor in
                    do {
                        let newPlayer = try AVAudioPlayer(contentsOf: rec.finalAudioURL())
                        newPlayer.delegate = playerDelegate
                        newPlayer.prepareToPlay()
                        
                        // Set playback session and start playing
                        setPlaybackSessionActive(true)
                        
                        if newPlayer.play() {
                            player = newPlayer
                            playingID = rec.id
                            isPlaying = true
                            playbackTime = 0
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } else {
                            throw NSError(domain: "PlaybackError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to start playback"])
                        }

                        // Ensure we deactivate session on finish
                        playerDelegate.onFinish = {
                            setPlaybackSessionActive(false)
                            isPlaying = false
                            playingID = nil
                            playbackTime = 0
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } catch {
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                        print("Playback error: \(error)")
                        // Reset states on error
                        isPlaying = false
                        playingID = nil
                        player = nil
                    }
                }
            }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func delete(at offsets: IndexSet) {
        // Stop playback and deactivate session if deleting current item
        if let currentID = playingID, let idx = offsets.first, recordings.indices.contains(idx), recordings[idx].id == currentID {
            player?.stop(); isPlaying = false; playingID = nil; setPlaybackSessionActive(false)
        }
        var toDelete: [Recording] = []
        for index in offsets { if recordings.indices.contains(index) { toDelete.append(recordings[index]) } }
        withAnimation { recordings.remove(atOffsets: offsets) }
        let store = RecordingDataStore(context: modelContext)
        for rec in toDelete {
            try? FileManager.default.removeItem(at: rec.finalAudioURL())
            try? store.deleteRecording(rec)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func format(duration: TimeInterval) -> String {
        let total = Int(duration)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    // Activate/deactivate playback audio session for reliable speaker output
    private func setPlaybackSessionActive(_ active: Bool) {
        // Run session changes on background queue to avoid blocking main thread
        Task {
            let session = AVAudioSession.sharedInstance()
            do {
                if active {
                    // Only change category if we're activating and no recording is active
                    if !di.audio.isSessionActive {
                        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                        try session.setActive(true, options: .notifyOthersOnDeactivation)
                    }
                } else {
                    // Don't deactivate if recording session is active
                    if !di.audio.isSessionActive {
                        try session.setActive(false, options: .notifyOthersOnDeactivation)
                    }
                }
            } catch {
                print("Playback session error: \(error)")
            }
        }
    }
}
