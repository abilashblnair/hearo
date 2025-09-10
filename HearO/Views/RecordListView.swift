import SwiftUI
import AVFoundation
import SwiftData
import UIKit
import UniformTypeIdentifiers

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
    
    // Audio file import state
    @State private var showingAudioFilePicker: Bool = false
    @State private var showingUploadSavePopup: Bool = false
    @State private var importedAudioURL: URL?
    @State private var importedDuration: TimeInterval = 0
    @State private var isImportingAudio: Bool = false
    @State private var importError: String?

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
            .overlay(alignment: .bottomTrailing) {
                // Floating + button for audio file upload
                if !di.audio.isSessionActive && !isMultiSelectMode {
                    floatingUploadButton
                        .padding(.trailing, 16)
                        .padding(.bottom, 100) // Space for safe area and mini recorder if present
                }
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
            .alert("Import Error", isPresented: .constant(importError != nil)) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
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
            .sheet(isPresented: $showingAudioFilePicker) {
                AudioDocumentPicker { url in
                    Task { await handleAudioFileSelection(url) }
                }
            }
            .overlay {
                if showingUploadSavePopup, let url = importedAudioURL {
                SaveRecordingPopupView(
                    duration: importedDuration,
                    onSave: { title, notes, folder in
                        Task { await saveImportedRecording(url: url, title: title, notes: notes, folder: folder) }
                    },
                    onCancel: {
                        cancelAudioImportAndCleanup()  // User cancelled - delete the file
                    }
                )
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .center)))
                    .zIndex(1000)
                }
            }
            .overlay {
                if isImportingAudio {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Processing audio file...")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 0.5))
                    }
            }
        }
        .navigationTitle("Recordings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Start Recording", systemImage: "record.circle.fill") {
                        showRecordingSheet = true
                    }
                    
                    if !recordings.isEmpty {
                        Divider()
                        if isMultiSelectMode {
                            Button("Cancel Selection") {
                                exitMultiSelectMode()
                            }
                        } else {
                            Button("Select Recordings", systemImage: "checkmark.circle") {
                                enterMultiSelectMode()
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button("Import Audio File", systemImage: "plus.circle") {
                        showingAudioFilePicker = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
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
                                    if !isSeeking {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                                    isSeeking = true
                                    let progress = max(0, min(1, value.location.x / geometry.size.width))
                                    seekTime = progress * totalDuration
                                }
                                .onEnded { value in
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
                segments = cachedSegments
            } else {
                let audioURL = rec.finalAudioURL()
                
                
                // Additional file info
                if FileManager.default.fileExists(atPath: audioURL.path) {
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
                        let _ = attributes[.size] as? Int64 ?? 0
                    } catch {
                    }
                } else {
                    
                    // Check if file exists with different UUID
                    let audioDir = audioURL.deletingLastPathComponent()
                    if let files = try? FileManager.default.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil) {
                        for _ in files {
                        }
                    }
                }
                
                segments = try await di.transcription.transcribe(audioURL: audioURL, languageCode: languageCode)

                // Cache the transcript in the Recording model
                rec.cacheTranscript(segments: segments, language: languageCode)

                // Save to persistent storage
                try modelContext.save()

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
    
    // MARK: - Floating Upload Button
    
    private var floatingUploadButton: some View {
        Button(action: {
            showingAudioFilePicker = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }) {
            ZStack {
                // Main button background
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                
                // Plus icon
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .scaleEffect(isImportingAudio ? 0.9 : 1.0)
        .opacity(isImportingAudio ? 0.7 : 1.0)
        .disabled(isImportingAudio)
        .animation(.easeInOut(duration: 0.2), value: isImportingAudio)
    }
    
    // MARK: - Audio File Import Methods
    
    @MainActor
    private func handleAudioFileSelection(_ url: URL) async {
        isImportingAudio = true
        defer { isImportingAudio = false }
        
        do {
            // Get file access and copy to app sandbox
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "AudioImportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not access selected file"])
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Validate the original file first
            let originalAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let originalSize = originalAttributes[.size] as? Int64 ?? 0
            guard originalSize > 0 else {
                throw NSError(domain: "AudioImportError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Selected file is empty"])
            }
            
            // Check if it's a valid audio file before copying
            let tempAsset = AVAsset(url: url)
            
            // Check for DRM protection first (most common issue)
            do {
                let hasProtectedContent = try await tempAsset.load(.hasProtectedContent)
                if hasProtectedContent {
                    throw NSError(domain: "AudioImportError", code: 8, userInfo: [
                        NSLocalizedDescriptionKey: "This audio file is protected by DRM (Digital Rights Management) and cannot be imported. Please choose an unprotected audio file, such as one you recorded yourself or downloaded from a DRM-free source."
                    ])
                }
            } catch {
                if (error as NSError).domain == "AudioImportError" {
                    throw error
                }
            }
            
            // Check basic readability
            let isReadable = try await tempAsset.load(.isReadable)
            let isPlayable = try await tempAsset.load(.isPlayable)
            
            guard isReadable && isPlayable else {
                throw NSError(domain: "AudioImportError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Selected file is not a valid audio format or is corrupted. Please choose an MP3, M4A, WAV, or other supported audio file."])
            }
            
            // Create destination URL in audio directory  
            let id = UUID()
            let destinationURL = try AudioFileStore.url(for: id)
            
            
            // Ensure audio directory exists
            let audioDir = destinationURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
            
            // Copy file to sandbox
            try FileManager.default.copyItem(at: url, to: destinationURL)
            
            
            // Verify the copied file
            let copiedAttributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
            let copiedSize = copiedAttributes[.size] as? Int64 ?? 0
            guard copiedSize > 0 && copiedSize == originalSize else {
                throw NSError(domain: "AudioImportError", code: 7, userInfo: [NSLocalizedDescriptionKey: "File copy was incomplete or corrupted"])
            }
            
            // Get audio duration from the copied file
            let duration = try await getAudioDuration(from: destinationURL)
            
            // Store for save popup
            importedAudioURL = destinationURL
            importedDuration = duration
            
            
            showingUploadSavePopup = true
            
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            
            // Clean up any partially copied file
            if let tempURL = try? AudioFileStore.url(for: UUID()) {
                try? FileManager.default.removeItem(at: tempURL)
            }
            
            // Show user-friendly error
            await MainActor.run {
                self.importError = error.localizedDescription
            }
        }
    }
    
    private func getAudioDuration(from url: URL) async throws -> TimeInterval {
        // Verify file exists and is readable
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "AudioImportError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Audio file does not exist at path: \(url.path)"])
        }
        
        // Check file size (avoid zero-byte files)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        guard fileSize > 0 else {
            throw NSError(domain: "AudioImportError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Audio file is empty or corrupted"])
        }
        
        // Create asset and validate it's readable
        let asset = AVAsset(url: url)
        
        // Try multiple approaches to get duration
        return try await getDurationWithFallback(asset: asset, url: url)
    }
    
    private func getDurationWithFallback(asset: AVAsset, url: URL) async throws -> TimeInterval {
        // Method 1: Try basic duration property first (most efficient)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            
            if seconds > 0 && !seconds.isNaN && !seconds.isInfinite {
                return seconds
            }
        } catch {
        }
        
        // Method 2: Try with AVAudioPlayer as fallback
        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            let duration = audioPlayer.duration
            
            if duration > 0 && !duration.isNaN && !duration.isInfinite {
                return duration
            }
        } catch {
        }
        
        // Method 3: Check if file is DRM protected
        do {
            let isPlayable = try await asset.load(.isPlayable)
            let hasProtectedContent = try await asset.load(.hasProtectedContent)
            
            if hasProtectedContent {
                throw NSError(domain: "AudioImportError", code: 8, userInfo: [
                    NSLocalizedDescriptionKey: "This audio file is protected by DRM (Digital Rights Management) and cannot be imported. Please use an unprotected audio file."
                ])
            }
            
            if !isPlayable {
                throw NSError(domain: "AudioImportError", code: 9, userInfo: [
                    NSLocalizedDescriptionKey: "This audio file format is not playable on this device."
                ])
            }
        } catch {
            if (error as NSError).domain == "AudioImportError" {
                throw error
            }
        }
        
        // Method 4: Try to get tracks and basic info
        do {
            let tracks = try await asset.load(.tracks)
            let isReadable = try await asset.load(.isReadable)
            
            guard isReadable else {
                throw NSError(domain: "AudioImportError", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "Audio file format is not supported or file is corrupted"
                ])
            }
            
            guard !tracks.isEmpty else {
                throw NSError(domain: "AudioImportError", code: 5, userInfo: [
                    NSLocalizedDescriptionKey: "Audio file contains no playable tracks"
                ])
            }
            
            // For unknown duration, provide a default that user can correct later
            return 60.0 // Default 1 minute - user can edit if needed
            
        } catch {
            if (error as NSError).domain == "AudioImportError" {
                throw error
            }
        }
        
        // Final fallback error
        throw NSError(domain: "AudioImportError", code: 6, userInfo: [
            NSLocalizedDescriptionKey: "Unable to process this audio file. It may be corrupted, in an unsupported format, or protected by DRM. Please try a different file."
        ])
    }
    
    @MainActor
    private func saveImportedRecording(url: URL, title: String, notes: String?, folder: RecordingFolder?) async {
        do {
            // CRITICAL FIX: Extract the UUID that was used when copying the file
            let _ = url.lastPathComponent // e.g., "B1343830-8535-4ED4-B764-25562E6E7658.m4a"
            let filenameWithoutExtension = url.deletingPathExtension().lastPathComponent
            
            
            // CRITICAL: Use the EXACT same UUID that was used for the file copy
            guard let recordingId = UUID(uuidString: filenameWithoutExtension) else {
                throw NSError(domain: "AudioImportError", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid file UUID format"])
            }
            
            
            // Verify the file actually exists at the expected location
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw NSError(domain: "AudioImportError", code: 11, userInfo: [NSLocalizedDescriptionKey: "Imported audio file was not found at expected location"])
            }
            
            
            // Store the SAME path format that AudioFileStore uses for consistency
            // This ensures finalAudioURL() resolves to the exact same path
            let relativePath = "audio/\(recordingId.uuidString).m4a"
            
            let recording = Recording(
                id: recordingId,
                title: title,
                createdAt: Date(),
                audioURL: relativePath,
                duration: importedDuration,
                notes: notes,
                folder: folder
            )
            
            // CRITICAL VERIFICATION: Ensure Recording can find its audio file before saving
            let resolvedURL = recording.finalAudioURL()
            
            // Debug path resolution
            debugFilePathResolution(recording: recording, expectedURL: url, resolvedURL: resolvedURL)
            
            
            // CRITICAL CHECK: The Recording MUST be able to find its own file
            guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
                
                // If paths don't match, there's a UUID inconsistency issue
                if resolvedURL.path != url.path {
                    throw NSError(domain: "AudioImportError", code: 12, userInfo: [NSLocalizedDescriptionKey: "UUID mismatch between Recording and imported file"])
                }
                
                throw NSError(domain: "AudioImportError", code: 12, userInfo: [NSLocalizedDescriptionKey: "Recording cannot locate its audio file"])
            }
            
            
            let folderStore = FolderDataStore(context: modelContext)
            try folderStore.saveRecording(recording, to: folder)
            
            NotificationCenter.default.post(name: .didSaveRecording, object: nil)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            
            // Clean up state (but keep the file since it was successfully saved)
            cancelAudioImport()
            
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            
            // Show user-friendly error
            await MainActor.run {
                self.importError = error.localizedDescription
            }
        }
    }
    
    private func cancelAudioImport() {
        // Reset state variables only - DO NOT DELETE FILES
        // Files should only be deleted if user explicitly cancels before saving
        
        importedAudioURL = nil
        importedDuration = 0
        showingUploadSavePopup = false
    }
    
    private func cancelAudioImportAndCleanup() {
        // This version actually deletes the file - only for user cancellation
        if let url = importedAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
        
        importedAudioURL = nil
        importedDuration = 0
        showingUploadSavePopup = false
    }
    
    // MARK: - Debug Utilities
    
    private func debugFilePathResolution(recording: Recording, expectedURL: URL, resolvedURL: URL) {
        
        // Check Documents directory
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let _ = docs.appendingPathComponent("audio")
        }
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
        
        
        // Update elapsed time to trigger UI refresh
        recElapsed = unifiedService.currentTime
        
        // Update prompt state to ensure it's closed after resume
        showMiniResumePrompt = false
        
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
            let folderStore = FolderDataStore(context: modelContext)
            // Save to default folder
            try folderStore.saveRecording(rec)
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
            return 
        }
        
        let clampedTime = max(0, min(time, player.duration))
        
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

// MARK: - Audio Document Picker

struct AudioDocumentPicker: UIViewControllerRepresentable {
    let onFileSelected: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            .audio,
            .mp3,
            .mpeg4Audio,
            UTType("com.microsoft.waveform-audio")!, // .wav
            UTType("public.aifc-audio")!, // .aiff
            UTType("public.aac-audio")!, // .aac
            UTType("org.xiph.flac")! // .flac
        ])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: AudioDocumentPicker
        
        init(_ parent: AudioDocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onFileSelected(url)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // Handle cancellation if needed
        }
    }
}


// MARK: - Activity View Controller (iOS 15 compatibility)

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
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
