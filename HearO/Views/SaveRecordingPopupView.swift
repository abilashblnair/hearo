import SwiftUI

struct SaveRecordingPopupView: View {
    let duration: TimeInterval
    let onSave: (String, String?, RecordingFolder?) -> Void
    let onCancel: () -> Void
    
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var isNotesExpanded: Bool = false
    @State private var selectedFolder: RecordingFolder?
    @State private var showingFolderPicker: Bool = false
    @State private var showingCreateFolder: Bool = false
    @State private var folders: [RecordingFolder] = []
    @State private var recentFolders: [RecordingFolder] = []
    
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNotesFocused: Bool
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var di: ServiceContainer
    @StateObject private var settings = SettingsService.shared
    
    private var defaultTitle: String {
        "Session " + Date.now.formatted(date: .abbreviated, time: .shortened)
    }
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }
            
            // Main popup card
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    // Success icon
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.1))
                            .frame(width: 64, height: 64)
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.green)
                    }
                    
                    Text("Recording Saved!")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Duration: \(timeString(from: duration))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 24)
                .padding(.horizontal, 24)
                
                // Form section
                VStack(spacing: 20) {
                    // Title field
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Title")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("(will use default)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        TextField("Enter recording title", text: $title)
                            .focused($isTitleFocused)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .submitLabel(.next)
                            .onSubmit {
                                isNotesFocused = true
                            }
                    }
                    
                    // Folder selection (only show if folder management is enabled)
                    if settings.isFolderManagementEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Save to Folder")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Button(action: { showingFolderPicker = true }) {
                                HStack(spacing: 12) {
                                    // Folder icon
                                    ZStack {
                                        Circle()
                                            .fill((selectedFolder?.color ?? .blue).opacity(0.2))
                                            .frame(width: 32, height: 32)
                                        
                                        Image(systemName: selectedFolder?.isDefault == true ? "folder.fill.badge.gearshape" : "folder.fill")
                                            .font(.body)
                                            .foregroundColor(selectedFolder?.color ?? .blue)
                                    }
                                    
                                    Text(selectedFolder?.name ?? "Select folder...")
                                        .foregroundColor(selectedFolder != nil ? .primary : .secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Notes section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Notes")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("(Optional)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isNotesExpanded.toggle()
                                    if isNotesExpanded {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            isNotesFocused = true
                                        }
                                    }
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isNotesExpanded ? "chevron.up" : "chevron.down")
                                        .font(.caption)
                                    Text(isNotesExpanded ? "Collapse" : "Add notes")
                                        .font(.caption)
                                }
                                .foregroundColor(.accentColor)
                            }
                        }
                        
                        if isNotesExpanded {
                            VStack(alignment: .leading, spacing: 4) {
                                TextEditor(text: $notes)
                                    .focused($isNotesFocused)
                                    .frame(minHeight: 80, maxHeight: 120)
                                    .padding(8)
                                    .background(Color(.systemBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(.systemGray4), lineWidth: 1)
                                    )
                                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                                
                                Text("Add context, key topics, or important points about this recording")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .transition(.opacity)
                            }
                        } else if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("\(notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50))\(notes.count > 50 ? "..." : "")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                
                // Action buttons
                HStack(spacing: 12) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                    
                    Button("Save") {
                        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultTitle : title
                        let finalNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        let finalFolder = settings.isFolderManagementEnabled ? selectedFolder : nil
                        onSave(finalTitle, finalNotes, finalFolder)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .fontWeight(.semibold)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .background(Color(.systemBackground))
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 32)
            .scaleEffect(1.0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isNotesExpanded)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTitleFocused = true
            }
            if settings.isFolderManagementEnabled {
                loadFolders()
            }
        }
        .sheet(isPresented: $showingFolderPicker) {
            if settings.isFolderManagementEnabled {
                FolderPickerSheet(
                    folders: folders,
                    recentFolders: recentFolders,
                    selectedFolder: $selectedFolder,
                    showingCreateFolder: $showingCreateFolder
                )
            }
        }
        .sheet(isPresented: $showingCreateFolder) {
            if settings.isFolderManagementEnabled {
                CreateFolderSheet { name, color in
                    await createFolder(name: name, colorName: color)
                }
            }
        }
    }
    
    private func timeString(from interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func loadFolders() {
        let folderStore = FolderDataStore(context: modelContext)
        do {
            folders = try folderStore.fetchFolders()
            recentFolders = try folderStore.getRecentFolders()
            
            // Auto-select default folder if none selected
            if selectedFolder == nil {
                selectedFolder = try folderStore.fetchDefaultFolder()
            }
        } catch {
        }
    }
    
    private func createFolder(name: String, colorName: String) async {
        let folderStore = FolderDataStore(context: modelContext)
        do {
            let newFolder = RecordingFolder(name: name, colorName: colorName)
            try folderStore.saveFolder(newFolder)
            loadFolders()
            selectedFolder = newFolder
        } catch {
        }
    }
}

// MARK: - Folder Picker Sheet

struct FolderPickerSheet: View {
    let folders: [RecordingFolder]
    let recentFolders: [RecordingFolder]
    @Binding var selectedFolder: RecordingFolder?
    @Binding var showingCreateFolder: Bool
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                // Recent folders section
                if !recentFolders.isEmpty {
                    Section("Recent") {
                        ForEach(recentFolders) { folder in
                            FolderPickerRow(
                                folder: folder,
                                isSelected: selectedFolder?.id == folder.id
                            ) {
                                selectedFolder = folder
                                dismiss()
                            }
                        }
                    }
                }
                
                // All folders section
                Section("All Folders") {
                    ForEach(folders) { folder in
                        FolderPickerRow(
                            folder: folder,
                            isSelected: selectedFolder?.id == folder.id
                        ) {
                            selectedFolder = folder
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Select Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Folder") {
                        showingCreateFolder = true
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct FolderPickerRow: View {
    let folder: RecordingFolder
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Folder icon
                ZStack {
                    Circle()
                        .fill(folder.color.opacity(0.2))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: folder.isDefault ? "folder.fill.badge.gearshape" : "folder.fill")
                        .font(.title3)
                        .foregroundColor(folder.color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(folder.name)
                            .font(.body)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if folder.isDefault {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                        }
                    }
                    
                    Text("\(folder.recordingCount) recordings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SaveRecordingPopupView(
        duration: 125.5,
        onSave: { title, notes, folder in
        },
        onCancel: {
        }
    )
}

