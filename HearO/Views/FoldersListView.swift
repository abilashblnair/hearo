import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AVFoundation

struct FoldersListView: View {
    @EnvironmentObject var di: ServiceContainer
    @Environment(\.modelContext) private var modelContext
    @Binding var showRecordingSheet: Bool
    @Binding var navigateToTranscript: Bool
    @Binding var currentTranscriptSession: Session?
    @Binding var currentTranscriptRecording: Recording?
    
    @State private var folders: [RecordingFolder] = []
    @State private var recentFolders: [RecordingFolder] = []
    @State private var isLoading = true
    @State private var showingCreateFolder = false
    @State private var showingEditFolder: RecordingFolder?
    @State private var selectedFolder: RecordingFolder?
    @State private var showingFolderDetail = false
    
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
                // Main content
                if isLoading {
                    ProgressView().padding()
                } else {
                    foldersList
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Floating + button for audio file upload
            floatingUploadButton
                .padding(.trailing, 16)
                .padding(.bottom, 100) // Space for safe area
        }
        .onAppear {
            Task { await loadFolders() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didSaveRecording)) { _ in
            Task { await loadFolders() }
        }
        .sheet(isPresented: $showingCreateFolder) {
            CreateFolderSheet { name, color in
                await createFolder(name: name, colorName: color)
            }
        }
        .sheet(item: $showingEditFolder) { folder in
            EditFolderSheet(folder: folder) { updatedFolder in
                await updateFolder(updatedFolder)
            }
        }
        .navigationDestination(isPresented: $showingFolderDetail) {
            if let folder = selectedFolder {
                FolderDetailView(
                    folder: folder,
                    showRecordingSheet: $showRecordingSheet,
                    navigateToTranscript: $navigateToTranscript,
                    currentTranscriptSession: $currentTranscriptSession,
                    currentTranscriptRecording: $currentTranscriptRecording
                )
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
        .alert("Import Error", isPresented: .constant(importError != nil)) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }
    
    // MARK: - Folders List
    
    private var foldersList: some View {
        List {
            // Recent folders section (if any)
            if !recentFolders.isEmpty {
                Section {
                    ForEach(recentFolders) { folder in
                        RecentFolderRow(folder: folder) {
                            openFolder(folder)
                        }
                    }
                } header: {
                    Label("Recent", systemImage: "clock")
                }
            }
            
            // All folders section
            Section {
                ForEach(folders) { folder in
                    FolderRow(folder: folder) {
                        openFolder(folder)
                    } onEdit: {
                        showingEditFolder = folder
                    } onDelete: {
                        deleteFolder(folder)
                    }
                }
                .onDelete(perform: deleteFolders)
            } header: {
                HStack {
                    Label("All Folders", systemImage: "folder")
                    Spacer()
                    Button(action: { showingCreateFolder = true }) {
                        Image(systemName: "plus")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: folders)
        .overlay {
            if !isLoading && folders.isEmpty {
                ContentUnavailableView {
                    Label("No folders yet", systemImage: "folder")
                } description: {
                    Text("Create your first folder to organize recordings.")
                } actions: {
                    Button("Create Folder") { showingCreateFolder = true }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Actions
    
    private func openFolder(_ folder: RecordingFolder) {
        selectedFolder = folder
        showingFolderDetail = true
    }
    
    @MainActor
    private func loadFolders() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let folderStore = FolderDataStore(context: modelContext)
            folders = try folderStore.fetchFolders()
            recentFolders = try folderStore.getRecentFolders()
        } catch {
        }
    }
    
    @MainActor
    private func createFolder(name: String, colorName: String) async {
        do {
            let folderStore = FolderDataStore(context: modelContext)
            let newFolder = RecordingFolder(name: name, colorName: colorName)
            try folderStore.saveFolder(newFolder)
            await loadFolders()
        } catch {
        }
    }
    
    @MainActor
    private func updateFolder(_ folder: RecordingFolder) async {
        do {
            let folderStore = FolderDataStore(context: modelContext)
            try folderStore.updateFolder(folder)
            await loadFolders()
        } catch {
        }
    }
    
    private func deleteFolder(_ folder: RecordingFolder) {
        if folder.isDefault {
            // Cannot delete default folder
            return
        }
        
        let folderStore = FolderDataStore(context: modelContext)
        do {
            try folderStore.deleteFolder(folder)
            Task { await loadFolders() }
        } catch {
        }
    }
    
    private func deleteFolders(at offsets: IndexSet) {
        let foldersToDelete = offsets.map { folders[$0] }
        for folder in foldersToDelete {
            deleteFolder(folder)
        }
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
            // Extract the UUID that was used when copying the file
            let _ = url.lastPathComponent // e.g., "B1343830-8535-4ED4-B764-25562E6E7658.m4a"
            let filenameWithoutExtension = url.deletingPathExtension().lastPathComponent
            
            
            // Use the same UUID that was used for the file copy
            guard let recordingId = UUID(uuidString: filenameWithoutExtension) else {
                throw NSError(domain: "AudioImportError", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid file UUID format"])
            }
            
            
            // Verify the file actually exists at the expected location
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw NSError(domain: "AudioImportError", code: 11, userInfo: [NSLocalizedDescriptionKey: "Imported audio file was not found at expected location"])
            }
            
            
            // Store relative path so sandbox container UUID changes don't break playbook
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
}

// MARK: - Supporting Views

struct FolderRow: View {
    let folder: RecordingFolder
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Folder icon with color
            ZStack {
                Circle()
                    .fill(folder.color.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: folder.isDefault ? "folder.fill.badge.gearshape" : "folder.fill")
                    .font(.title3)
                    .foregroundColor(folder.color)
            }
            
            // Folder info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(folder.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if folder.isDefault {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                }
                
                HStack(spacing: 8) {
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
            
            if folder.recordingCount > 0 {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            if !folder.isDefault {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
    }
    
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
}

struct RecentFolderRow: View {
    let folder: RecordingFolder
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Smaller folder icon
            ZStack {
                Circle()
                    .fill(folder.color.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: "folder.fill")
                    .font(.body)
                    .foregroundColor(folder.color)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(folder.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                if let lastDate = folder.latestRecordingDate {
                    Text(lastDate, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text("\(folder.recordingCount)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(folder.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(folder.color.opacity(0.1))
                .clipShape(Capsule())
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Create/Edit Folder Sheets

struct CreateFolderSheet: View {
    let onSave: (String, String) async -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var folderName = ""
    @State private var selectedColor = FolderColor.blue
    @FocusState private var isNameFocused: Bool
    
    var body: some View {
        NavigationView {
            Form {
                Section("Folder Details") {
                    TextField("Folder name", text: $folderName)
                        .focused($isNameFocused)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Color")
                            .font(.headline)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                            ForEach(FolderColor.allCases) { color in
                                Button {
                                    selectedColor = color
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(color.color)
                                            .frame(width: 40, height: 40)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.primary, lineWidth: selectedColor == color ? 3 : 0.5)
                                            )
                                            .shadow(color: color.color.opacity(0.3), radius: selectedColor == color ? 4 : 2)
                                        
                                        if selectedColor == color {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .scaleEffect(selectedColor == color ? 1.1 : 1.0)
                                    .animation(.easeInOut(duration: 0.2), value: selectedColor == color)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await onSave(folderName.isEmpty ? "New Folder" : folderName, selectedColor.name)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            isNameFocused = true
        }
    }
}

struct EditFolderSheet: View {
    let folder: RecordingFolder
    let onSave: (RecordingFolder) async -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var folderName: String
    @State private var selectedColor: FolderColor
    @FocusState private var isNameFocused: Bool
    
    init(folder: RecordingFolder, onSave: @escaping (RecordingFolder) async -> Void) {
        self.folder = folder
        self.onSave = onSave
        self._folderName = State(initialValue: folder.name)
        self._selectedColor = State(initialValue: FolderColor(rawValue: folder.colorName) ?? .blue)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Folder Details") {
                    TextField("Folder name", text: $folderName)
                        .focused($isNameFocused)
                        .disabled(folder.isDefault)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Color")
                            .font(.headline)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                            ForEach(FolderColor.allCases) { color in
                                Button {
                                    selectedColor = color
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(color.color)
                                            .frame(width: 40, height: 40)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.primary, lineWidth: selectedColor == color ? 3 : 0.5)
                                            )
                                            .shadow(color: color.color.opacity(0.3), radius: selectedColor == color ? 4 : 2)
                                        
                                        if selectedColor == color {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .scaleEffect(selectedColor == color ? 1.1 : 1.0)
                                    .animation(.easeInOut(duration: 0.2), value: selectedColor == color)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                
                if folder.isDefault {
                    Section {
                        Label("This is your default folder and cannot be renamed", systemImage: "info.circle")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if !folder.isDefault {
                                folder.name = folderName.isEmpty ? "Untitled Folder" : folderName
                            }
                            folder.colorName = selectedColor.name
                            await onSave(folder)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Audio Document Picker (duplicate for FoldersListView)

extension FoldersListView {
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
}
