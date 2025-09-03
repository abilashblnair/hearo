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
    @Binding var navigateToTranscript: Bool
    @Binding var currentTranscriptSession: Session?
    @Binding var currentTranscriptRecording: Recording?

    @State private var recordings: [Recording] = []
    @State private var isLoading = true

    // Playback state
    @State private var player: AVAudioPlayer?
    @State private var playingID: UUID?
    @State private var isPlaying: Bool = false
    @State private var playerDelegate = AudioPlayerDelegate()
    @State private var playbackTime: TimeInterval = 0
    @State private var isSeeking = false
    @State private var seekTime: TimeInterval = 0
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
    
    // Multi-selection and management state
    @State private var isMultiSelectMode: Bool = false
    @State private var selectedRecordings: Set<UUID> = []
    @State private var expandedRecordings: Set<UUID> = []
    
    // Interruption handling state
    @State private var showMiniResumePrompt = false
    @State private var showingRenameDialog: Bool = false
    @State private var renamingRecording: Recording? = nil
    @State private var newRecordingName: String = ""
    @State private var showingShareSheet: Bool = false
    @State private var shareItems: [Any] = []

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Multi-select toolbar
                if isMultiSelectMode {
                    multiSelectToolbar
                        .background(Color(.systemBackground))
                        .overlay(
                            Rectangle()
                                .frame(height: 0.5)
                                .foregroundColor(Color(.separator)),
                            alignment: .bottom
                        )
                }
                
                // Main content
                VStack(spacing: 12) {
                    // Lightweight header so the screen never looks empty
                    if isLoading {
                        ProgressView().padding()
                    } else {
                        recordList
                    }
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
                    isSeeking = false
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
                if isPlaying, let player, playingID != nil, !isSeeking { playbackTime = player.currentTime }
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
            .alert("Rename Recording", isPresented: $showingRenameDialog) {
                TextField("Recording name", text: $newRecordingName)
                Button("Rename") { renameCurrentRecording() }
                Button("Cancel", role: .cancel) { cancelRename() }
            } message: {
                Text("Enter a new name for your recording")
            }
            .alert("Resume Recording?", isPresented: $showMiniResumePrompt) {
                Button("Resume Recording") {
                    manualResumeMiniRecording()
                }
                Button("Stop Recording", role: .destructive) {
                    stopMiniAndPrompt()
                }
                Button("Not Now", role: .cancel) { 
                    showMiniResumePrompt = false
                }
            } message: {
                Text("Your call has ended. Would you like to resume recording or stop and save the current session?")
            }
            .sheet(isPresented: $showingShareSheet) {
                if #available(iOS 16.0, *) {
                    ShareSheet(items: shareItems)
                } else {
                    ActivityViewController(activityItems: shareItems)
                }
            }

    }
    // MARK: - Record List

    private var recordList: some View {
        Group {
            if isMultiSelectMode {
                List(selection: $selectedRecordings) {
                    ForEach(recordings) { rec in
                        recordingRow(for: rec)
                            .listRowSeparator(.visible)
                    }
                }
            } else {
                List {
                    ForEach(recordings) { rec in
                        recordingRow(for: rec)
                            .listRowSeparator(.visible)
                            .onLongPressGesture {
                                enterMultiSelectMode()
                                selectedRecordings.insert(rec.id)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                    }
                    .onDelete(perform: delete)
                }
            }
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
    
    // MARK: - Recording Row
    
    @ViewBuilder
    private func recordingRow(for rec: Recording) -> some View {
        let isRowPlaying = (playingID == rec.id && isPlaying)
        let totalDuration: TimeInterval = (isRowPlaying ? (player?.duration ?? rec.duration) : rec.duration)
        let isSelected = selectedRecordings.contains(rec.id)
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Multi-select checkbox
                if isMultiSelectMode {
                    Button(action: { toggleSelection(for: rec) }) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundColor(isSelected ? .accentColor : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 4)
                } else {
                    // Play/pause button
                    Button(action: { 
                        print("🎵 Play button tapped for: \(rec.title)")
                        togglePlayback(for: rec) 
                    }) {
                        Image(systemName: isRowPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 8)
                }
                
                // Recording info
                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.title).font(.body)
                    Text(rec.createdAt, style: .date) + Text(", ") + Text(rec.createdAt, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Show notes preview if available and cell is not expanded
                    if let notes = rec.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !expandedRecordings.contains(rec.id) {
                        Text(notes.prefix(60) + (notes.count > 60 ? "..." : ""))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                            .lineLimit(2)
                    }
                }
                .onTapGesture {
                    if !isMultiSelectMode {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expandedRecordings.contains(rec.id) {
                                expandedRecordings.remove(rec.id)
                            } else {
                                expandedRecordings.insert(rec.id)
                            }
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                
                Spacer()
                
                if !isMultiSelectMode {
                    // Transcribe button
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
                    .buttonStyle(.borderless)
                    .disabled(isTranscribing)
                    .opacity(isTranscribing ? 0.5 : 1.0)
                    
                    // 3-dot menu  
                    Menu {
                        Button(action: { startRename(rec) }) {
                            Label("Rename", systemImage: "pencil")
                        }
                        
                        Button(action: { shareRecording(rec) }) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: { deleteRecording(rec) }) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                }
            }
            
            // Playback controls
            if playingID == rec.id && !isMultiSelectMode {
                HStack(spacing: 8) {
                    Text(format(duration: isSeeking ? seekTime : playbackTime))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(isSeeking ? .blue : .secondary)
                    
                    // Interactive seek slider with custom gesture handling
                    GeometryReader { geometry in
                        ZStack {
                            // Background track
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(.systemGray4))
                                .frame(height: 4)
                            
                            // Progress track
                            HStack {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.blue)
                                    .frame(height: 4)
                                    .frame(width: max(0, CGFloat(totalDuration > 0 ? (isSeeking ? seekTime : playbackTime) / totalDuration : 0) * geometry.size.width))
                                Spacer(minLength: 0)
                            }
                            
                            // Slider thumb
                            HStack {
                                Spacer()
                                    .frame(width: max(0, CGFloat(totalDuration > 0 ? (isSeeking ? seekTime : playbackTime) / totalDuration : 0) * geometry.size.width - 8))
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 16, height: 16)
                                    .scaleEffect(isSeeking ? 1.2 : 1.0)
                                    .animation(.easeInOut(duration: 0.1), value: isSeeking)
                                Spacer()
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    print("🎯 Custom drag gesture changed: \(value.location.x) / \(geometry.size.width)")
                                    if !isSeeking {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                                    isSeeking = true
                                    let progress = max(0, min(1, value.location.x / geometry.size.width))
                                    seekTime = progress * totalDuration
                                }
                                .onEnded { value in
                                    print("🎯 Custom drag gesture ended")
                                    let progress = max(0, min(1, value.location.x / geometry.size.width))
                                    seekTime = progress * totalDuration
                                    seekToTime(seekTime)
                                    isSeeking = false
                                }
                        )
                    }
                                            .frame(height: 44) // Larger touch target
                    
                    Text(format(duration: totalDuration))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            
            // Expanded notes section
            if expandedRecordings.contains(rec.id), let notes = rec.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "note.text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Notes")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    Text(notes.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.caption)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .slide))
            }
        }
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .animation(.easeInOut(duration: 0.2), value: expandedRecordings.contains(rec.id))
    }
    
    // MARK: - Multi-Select Toolbar
    
    private var multiSelectToolbar: some View {
        HStack {
            Button("Cancel") {
                exitMultiSelectMode()
            }
            .foregroundColor(.accentColor)
            
            Spacer()
            
            Text("\(selectedRecordings.count) selected")
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            HStack(spacing: 16) {
                if !selectedRecordings.isEmpty {
                    Button(action: shareSelectedRecordings) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                    }
                    .disabled(selectedRecordings.isEmpty)
                    
                    Button(action: deleteSelectedRecordings) {
                        Image(systemName: "trash")
                            .font(.title3)
                            .foregroundColor(.red)
                    }
                    .disabled(selectedRecordings.isEmpty)
                } else {
                    Button("Select All") {
                        selectedRecordings = Set(recordings.map { $0.id })
                    }
                    .foregroundColor(.accentColor)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                isSeeking = false
                setPlaybackSessionActive(false)
            }

            navigateToTranscript = true
        } catch {
            transcribeError = error.localizedDescription
        }
    }
    
    // MARK: - Multi-Selection & Menu Actions
    
    private func enterMultiSelectMode() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isMultiSelectMode = true
            selectedRecordings.removeAll()
        }
    }
    
    private func exitMultiSelectMode() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isMultiSelectMode = false
            selectedRecordings.removeAll()
        }
    }
    
    private func toggleSelection(for recording: Recording) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedRecordings.contains(recording.id) {
                selectedRecordings.remove(recording.id)
            } else {
                selectedRecordings.insert(recording.id)
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func startRename(_ recording: Recording) {
        renamingRecording = recording
        newRecordingName = recording.title
        showingRenameDialog = true
    }
    
    private func renameCurrentRecording() {
        guard let recording = renamingRecording else { return }
        let trimmedName = newRecordingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            renameRecording(recording, newName: trimmedName)
        }
        cancelRename()
    }
    
    private func cancelRename() {
        renamingRecording = nil
        newRecordingName = ""
        showingRenameDialog = false
    }
    
    private func renameRecording(_ recording: Recording, newName: String) {
        // Update the recording title
        recording.title = newName
        
        // Save to context
        do {
            try modelContext.save()
            // Reload recordings to reflect the change
            Task { await loadRecordings() }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            print("Failed to save renamed recording: \(error)")
        }
    }
    
    private func shareRecording(_ recording: Recording) {
        let audioURL = recording.finalAudioURL()
        shareItems = [audioURL]
        showingShareSheet = true
    }
    
    private func shareSelectedRecordings() {
        let urls = recordings.filter { selectedRecordings.contains($0.id) }
                            .map { $0.finalAudioURL() }
        shareItems = urls
        showingShareSheet = true
    }
    
    private func deleteRecording(_ recording: Recording) {
        // Stop playback if this recording is currently playing
        if playingID == recording.id {
            player?.stop()
            isPlaying = false
            playingID = nil
            isSeeking = false
            setPlaybackSessionActive(false)
        }
        
        // Delete from storage
        let store = RecordingDataStore(context: modelContext)
        do {
            try FileManager.default.removeItem(at: recording.finalAudioURL())
            try store.deleteRecording(recording)
            
            // Remove from local array
            withAnimation {
                if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
                    recordings.remove(at: index)
                }
            }
            
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            print("Failed to delete recording: \(error)")
        }
    }
    
    private func deleteSelectedRecordings() {
        let recordingsToDelete = recordings.filter { selectedRecordings.contains($0.id) }
        
        // Stop playback if current item is being deleted
        if let currentID = playingID, selectedRecordings.contains(currentID) {
            player?.stop()
            isPlaying = false
            playingID = nil
            isSeeking = false
            setPlaybackSessionActive(false)
        }
        
        let store = RecordingDataStore(context: modelContext)
        
        withAnimation {
            // Remove from local array first for immediate UI feedback
            recordings.removeAll { selectedRecordings.contains($0.id) }
        }
        
        // Delete files and database records
        for recording in recordingsToDelete {
            do {
                try FileManager.default.removeItem(at: recording.finalAudioURL())
                try store.deleteRecording(recording)
            } catch {
                print("Failed to delete recording \(recording.title): \(error)")
            }
        }
        
        exitMultiSelectMode()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
                        Circle().fill(getStatusColor())
                            .frame(width: 10, height: 10)
                            .opacity(di.audio.isRecording ? 1 : 0.6)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: di.audio.isRecording)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(getStatusText())
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
        // Check if there are pending resume operations (interruption state)
        if let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl,
           unifiedService.hasPendingResumeOperations {
            // Show resume prompt for interrupted recording
            showMiniResumePrompt = true
            return
        }
        
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
    
    private func manualResumeMiniRecording() {
        if let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl {
            unifiedService.forceResumeAfterInterruption()
            
            // Give a small delay for the audio service to process the resume
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.syncMiniRecorderState()
            }
            
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
    
    private func syncMiniRecorderState() {
        guard let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl else { return }
        
        print("🔄 Syncing mini recorder state after manual resume")
        print("📊 Mini recorder state: Recording=\(unifiedService.isRecording), Transcription=\(unifiedService.isTranscriptionActive)")
        
        // Update elapsed time to trigger UI refresh
        recElapsed = unifiedService.currentTime
        
        // Update prompt state to ensure it's closed after resume
        showMiniResumePrompt = false
        
        print("✅ Mini recorder state synced")
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
        // Store relative path so sandbox container UUID changes don't break playbook
        let relativePath = "audio/\(id.uuidString).m4a"
        let rec = Recording(id: id, title: title, createdAt: Date(), audioURL: relativePath, duration: miniLastDuration, notes: nil)
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

    private func seekToTime(_ time: TimeInterval) {
        guard let player = player else { 
            print("❌ RecordListView seekToTime: No audio player available")
            return 
        }
        
        let clampedTime = max(0, min(time, player.duration))
        print("🎯 RecordListView seeking to time: \(clampedTime) (requested: \(time), duration: \(player.duration))")
        
        player.currentTime = clampedTime
        playbackTime = clampedTime
        
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func togglePlayback(for rec: Recording) {
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
            isSeeking = false

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
                        isSeeking = false
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } catch {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    print("Playback error: \(error)")
                    // Reset states on error
                    isPlaying = false
                    playingID = nil
                    player = nil
                    isSeeking = false
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        // Stop playback and deactivate session if deleting current item
        if let currentID = playingID, let idx = offsets.first, recordings.indices.contains(idx), recordings[idx].id == currentID {
            player?.stop(); isPlaying = false; playingID = nil; isSeeking = false; setPlaybackSessionActive(false)
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
    
    // MARK: - Interruption Status Helpers
    
    private func getStatusColor() -> Color {
        if let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl {
            // Check if there are pending operations (interruption state)
            if unifiedService.hasPendingResumeOperations {
                return Color.yellow // Interrupted state
            }
        }
        return di.audio.isRecording ? Color.red : Color.orange
    }
    
    private func getStatusText() -> String {
        if let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl {
            // Check if there are pending operations (interruption state)
            if unifiedService.hasPendingResumeOperations {
                return "Call in progress"
            }
        }
        return di.audio.isRecording ? "Recording…" : "Paused"
    }
}

// MARK: - Share Sheet Components

@available(iOS 16.0, *)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}
