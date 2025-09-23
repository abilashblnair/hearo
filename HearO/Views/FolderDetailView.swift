import SwiftUI
import AVFoundation
import SwiftData
import UIKit

struct FolderDetailView: View {
    let folder: RecordingFolder
    @EnvironmentObject var di: ServiceContainer
    @Environment(\.modelContext) private var modelContext
    let onStartRecording: () -> Void
    let onExpandRecording: () -> Void
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

    // Multi-selection and management state
    @State private var isMultiSelectMode: Bool = false
    @State private var selectedRecordings: Set<UUID> = []
    @State private var expandedRecordings: Set<UUID> = []

    // Recording management state
    @State private var showingRenameDialog: Bool = false
    @State private var renamingRecording: Recording? = nil
    @State private var newRecordingName: String = ""
    @State private var showingShareSheet: Bool = false
    @State private var shareItems: [Any] = []

    // Transcription state
    @State private var isTranscribing: Bool = false
    @State private var transcribingRecordingID: UUID? = nil
    @State private var transcribeError: String? = nil


    // Folder management state
    @State private var showingEditFolder: Bool = false
    @State private var showingDeleteFolderAlert: Bool = false

    // Retention policy state
    @State private var showingRetentionAlert = false
    @State private var selectedRecordingForRetention: Recording? = nil

    // Paywall state
    @State private var showPaywall = false

    // Mini recorder state
    @State private var recElapsed: TimeInterval = 0
    @State private var showMiniSavePrompt = false
    @State private var miniNameText: String = ""
    @State private var miniLastDuration: TimeInterval = 0
    @State private var miniCollapsed: Bool = false
    @State private var miniURL: URL? = nil
    @State private var showMiniResumePrompt = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Folder header
                folderHeader

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

                // Recordings list
                if isLoading {
                    ProgressView().padding()
                } else {
                    recordingsList
                }
            }

            // Transcription progress overlay
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
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(nil, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Start Recording", systemImage: "record.circle.fill") {
                        onStartRecording()
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

                    Button("Edit Folder", systemImage: "folder.badge.gearshape") {
                        showingEditFolder = true
                    }

                    if !folder.isDefault {
                        Button("Delete Folder", systemImage: "trash") {
                            showingDeleteFolderAlert = true
                        }
                        .foregroundColor(.red)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
        }
        .paywall(isPresented: $showPaywall, placementId: AppConfigManager.shared.adaptyPlacementID)
        .onAppear {
            Task { await loadRecordings() }
            setupPlayerDelegate()

            // Ensure any recording session is properly cleaned up
            if !di.audio.isRecording {
                di.audio.deactivateSessionIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didSaveRecording)) { _ in
            Task { await loadRecordings() }
        }
        .onReceive(playbackTimer) { _ in
            if isPlaying, let player, playingID != nil, !isSeeking {
                playbackTime = player.currentTime
            }
            if di.audio.isSessionActive {
                if di.audio.isRecording { di.audio.updateMeters() }
                recElapsed = di.audio.currentTime
            }
        }
        .overlay(alignment: .bottom) {
            if di.audio.isSessionActive {
                miniBar.padding(.horizontal)
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
        .alert("Rename Recording", isPresented: $showingRenameDialog) {
            TextField("Recording name", text: $newRecordingName)
            Button("Rename") { renameCurrentRecording() }
            Button("Cancel", role: .cancel) { cancelRename() }
        } message: {
            Text("Enter a new name for your recording")
        }
        .alert("Resume Recording?", isPresented: $showMiniResumePrompt) {
            Button("Resume Recording") { manualResumeMiniRecording() }
            Button("Stop Recording", role: .destructive) { stopMiniAndPrompt() }
            Button("Not Now", role: .cancel) { showMiniResumePrompt = false }
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
        .sheet(isPresented: $showingEditFolder) {
            EditFolderSheet(folder: folder) { updatedFolder in
                await updateFolder(updatedFolder)
            }
        }
        .alert("Delete Folder", isPresented: $showingDeleteFolderAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteFolder()
            }
        } message: {
            Text("This will permanently delete the folder '\(folder.name)' and move all recordings to the default folder. This action cannot be undone.")
        }
        .alert("Recording Will Be Deleted", isPresented: $showingRetentionAlert) {
            Button("Upgrade to Premium") {
                showPaywallForRetentionWarning()
            }
            Button("OK", role: .cancel) {
                selectedRecordingForRetention = nil
            }
        } message: {
            if let recording = selectedRecordingForRetention {
                let daysRemaining = getDaysUntilDeletion(for: recording)
                if daysRemaining <= 0 {
                    Text("This recording will be automatically deleted soon as it's older than 7 days. Upgrade to Premium to keep all your recordings forever!")
                } else {
                    Text("This recording will be automatically deleted in \(daysRemaining) day\(daysRemaining == 1 ? "" : "s"). Upgrade to Premium to keep all your recordings forever!")
                }
            } else {
                Text("Free users can only keep recordings for 7 days. Upgrade to Premium for unlimited history!")
            }
        }
    }

    // MARK: - Folder Header

    private var folderHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Folder icon
                ZStack {
                    Circle()
                        .fill(folder.color.opacity(0.2))
                        .frame(width: 50, height: 50)

                    Image(systemName: folder.isDefault ? "folder.fill.badge.gearshape" : "folder.fill")
                        .font(.title2)
                        .foregroundColor(folder.color)
                }

                // Folder stats
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(folder.name)
                            .font(.title3)
                            .fontWeight(.semibold)

                        if folder.isDefault {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                    }

                    HStack(spacing: 12) {
                        Label("\(folder.recordingCount)", systemImage: "waveform")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if folder.totalDuration > 0 {
                            Label(timeString(from: folder.totalDuration), systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Recordings List

    private var recordingsList: some View {
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
                    Label("No recordings in this folder", systemImage: "waveform")
                } description: {
                    Text("Start recording to add your first clip to \"\(folder.name)\".")
                } actions: {
                    Button("Start Recording") { onStartRecording() }
                }
                .padding()
            }
        }
    }

    // MARK: - Recording Row (Reused from RecordListView)

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
                    Button(action: { togglePlayback(for: rec) }) {
                        Image(systemName: isRowPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 8)
                }

                // Recording info
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(rec.title).font(.body)
                        Spacer()
                        // Retention badge for free users
                        if !di.subscription.isPremium {
                            retentionBadge(for: rec)
                        }
                    }
                    Text(rec.createdAt, style: .date) + Text(", ") + Text(rec.createdAt, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Show notes preview if available
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

            // Playback controls (same as RecordListView)
            if playingID == rec.id && !isMultiSelectMode {
                playbackControls(for: rec, totalDuration: totalDuration)
            }

            // Expanded notes section
            if expandedRecordings.contains(rec.id), let notes = rec.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                expandedNotesSection(notes: notes)
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

    // MARK: - Helper Views

    private func playbackControls(for rec: Recording, totalDuration: TimeInterval) -> some View {
        HStack(spacing: 8) {
            Text(format(duration: isSeeking ? seekTime : playbackTime))
                .font(.caption.monospacedDigit())
                .foregroundColor(isSeeking ? .blue : .secondary)

            // Interactive seek slider
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
            .frame(height: 44)

            Text(format(duration: totalDuration))
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }

    private func expandedNotesSection(notes: String) -> some View {
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

    // Mini recorder bar (same as RecordListView)
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
                Button(action: { onExpandRecording() }) {
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
                Button(action: { onExpandRecording() }) {
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

    // MARK: - Recording Control Functions

    // MARK: - Actions and Helper Methods (Similar to RecordListView)

    @MainActor
    private func loadRecordings() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let folderStore = FolderDataStore(context: modelContext)
            recordings = try folderStore.fetchRecordings(in: folder)
        } catch {
        }
    }

    private func setupPlayerDelegate() {
        playerDelegate.onFinish = {
            isPlaying = false
            playingID = nil
            playbackTime = 0
            isSeeking = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // Include other methods from RecordListView (transcribeRecording, togglePlayback, etc.)
    // ... (For brevity, I'm not repeating all methods here, but they should be copied over)

    private func timeString(from interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func format(duration: TimeInterval) -> String {
        let total = Int(duration)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Transcription
    @MainActor
    private func transcribeRecording(_ rec: Recording) async {
        isTranscribing = true
        transcribingRecordingID = rec.id
        transcribeError = nil
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

                // Additional file existence check
                guard FileManager.default.fileExists(atPath: audioURL.path) else {
                    throw NSError(domain: "TranscriptionError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Audio file not found"])
                }

                segments = try await di.transcription.transcribe(audioURL: audioURL, languageCode: languageCode)

                // Cache the transcript in the Recording model
                rec.cacheTranscript(segments: segments, language: languageCode)

                // Save to persistent storage
                try modelContext.save()
            }

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

    // MARK: - Playback Controls

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

    // MARK: - Multi-Selection Management

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

    // MARK: - Recording Management

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
        let selectedRecs = recordings.filter { selectedRecordings.contains($0.id) }
        let shareUrls = selectedRecs.map { $0.finalAudioURL() }

        if !shareUrls.isEmpty {
            shareItems = shareUrls
            showingShareSheet = true
        }
    }

    private func deleteRecording(_ recording: Recording) {
        do {
            try RecordingDataStore(context: modelContext).deleteRecording(recording)
            Task { await loadRecordings() }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func deleteSelectedRecordings() {
        let selectedRecs = recordings.filter { selectedRecordings.contains($0.id) }

        for recording in selectedRecs {
            deleteRecording(recording)
        }

        exitMultiSelectMode()
    }

    private func updateFolder(_ updatedFolder: RecordingFolder) async {
        let folderStore = FolderDataStore(context: modelContext)
        do {
            try folderStore.saveFolder(updatedFolder)
        } catch {
        }
    }

    private func deleteFolder() {
        let folderStore = FolderDataStore(context: modelContext)
        do {
            // Move all recordings to default folder first
            if let defaultFolder = try folderStore.fetchDefaultFolder() {
                for recording in folder.recordings {
                    try folderStore.moveRecording(recording, to: defaultFolder)
                }
            }

            // Delete the folder
            try folderStore.deleteFolder(folder)

            UINotificationFeedbackGenerator().notificationOccurred(.success)

        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // MARK: - Additional Helper Methods

    private func delete(at offsets: IndexSet) {
        // Stop playback and deactivate session if deleting current item
        if let currentID = playingID, let idx = offsets.first, recordings.indices.contains(idx), recordings[idx].id == currentID {
            player?.stop()
            isPlaying = false
            playingID = nil
            isSeeking = false
            setPlaybackSessionActive(false)
        }

        var toDelete: [Recording] = []
        for index in offsets {
            if recordings.indices.contains(index) {
                toDelete.append(recordings[index])
            }
        }

        withAnimation {
            recordings.remove(atOffsets: offsets)
        }

        let store = RecordingDataStore(context: modelContext)
        for rec in toDelete {
            try? FileManager.default.removeItem(at: rec.finalAudioURL())
            try? store.deleteRecording(rec)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
                // No session -> need to start fresh recording, check limits
                onStartRecording()
            }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
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
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func saveMiniRecording() {
        guard let url = miniURL else { return }
        let filename = url.deletingPathExtension().lastPathComponent
        let id = UUID(uuidString: filename) ?? UUID()
        let title = miniNameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ("Session " + Date.now.formatted(date: .abbreviated, time: .shortened)) : miniNameText
        // Store relative path so sandbox container UUID changes don't break playbook
        let relativePath = "audio/\(id.uuidString).m4a"
        let rec = Recording(id: id, title: title, createdAt: Date(), audioURL: relativePath, duration: miniLastDuration, notes: nil, folder: folder)

        do {
            let folderStore = FolderDataStore(context: modelContext)
            try folderStore.saveRecording(rec, to: folder)
            NotificationCenter.default.post(name: .didSaveRecording, object: nil)
            miniNameText = ""
            showMiniSavePrompt = false
            miniURL = nil
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
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
    private func getStatusColor() -> Color {
        return di.audio.isRecording ? Color.red : Color.orange
    }

    private func getStatusText() -> String {
        return di.audio.isRecording ? "Recording…" : "Paused"
    }

    // MARK: - Retention Policy UI

    @ViewBuilder
    private func retentionBadge(for recording: Recording) -> some View {
        let daysRemaining = getDaysUntilDeletion(for: recording)
        let isUrgent = daysRemaining <= 3

        // Always show days remaining for free users
        Button(action: {
            if isUrgent {
                selectedRecordingForRetention = recording
                showingRetentionAlert = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }) {
            HStack(spacing: 3) {
                Image(systemName: getBadgeIcon(for: daysRemaining))
                    .font(.caption2)
                Text(getBadgeText(for: daysRemaining))
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundColor(getBadgeTextColor(for: daysRemaining))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(getBadgeBackgroundColor(for: daysRemaining))
            )
            .overlay(
                Capsule()
                    .strokeBorder(getBadgeBorderColor(for: daysRemaining), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isUrgent) // Only tappable when urgent
    }

    private func getDaysUntilDeletion(for recording: Recording) -> Int {
        let daysSinceRecording = Calendar.current.dateComponents([.day], from: recording.createdAt, to: Date()).day ?? 0
        return max(0, FeatureManager.FreeTierLimits.historyRetentionDays - daysSinceRecording)
    }

    // MARK: - Badge Styling Helpers

    private func getBadgeIcon(for daysRemaining: Int) -> String {
        switch daysRemaining {
        case 0:
            return "exclamationmark.triangle.fill"
        case 1...3:
            return "clock.fill"
        default:
            return "calendar"
        }
    }

    private func getBadgeText(for daysRemaining: Int) -> String {
        switch daysRemaining {
        case 0:
            return "Expires Today"
        case 1:
            return "1 day left"
        case 2...6:
            return "\(daysRemaining) days left"
        case 7:
            return "New"
        default:
            return "\(daysRemaining)d"
        }
    }

    private func getBadgeTextColor(for daysRemaining: Int) -> Color {
        switch daysRemaining {
        case 0:
            return .white
        case 1...3:
            return .white
        default:
            return .secondary
        }
    }

    private func getBadgeBackgroundColor(for daysRemaining: Int) -> Color {
        switch daysRemaining {
        case 0:
            return .red
        case 1:
            return .orange
        case 2...3:
            return .yellow
        default:
            return Color(.systemGray6)
        }
    }

    private func getBadgeBorderColor(for daysRemaining: Int) -> Color {
        switch daysRemaining {
        case 0...3:
            return .clear
        default:
            return Color(.systemGray4)
        }
    }

    private func showPaywallForRetentionWarning() {
        // Clear the retention alert state first
        selectedRecordingForRetention = nil

        // Trigger the paywall presentation
        showPaywall = true
    }
}
