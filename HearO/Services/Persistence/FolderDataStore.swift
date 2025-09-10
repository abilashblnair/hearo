import Foundation
import SwiftData

final class FolderDataStore {
    private let context: ModelContext
    
    init(context: ModelContext) {
        self.context = context
    }
    
    // MARK: - Folder Operations
    
    func saveFolder(_ folder: RecordingFolder) throws {
        context.insert(folder)
        try context.save()
    }
    
    func fetchFolders() throws -> [RecordingFolder] {
        let descriptor = FetchDescriptor<RecordingFolder>()
        let folders = try context.fetch(descriptor)
        
        // Sort manually: default first, then by creation date
        return folders.sorted { folder1, folder2 in
            if folder1.isDefault != folder2.isDefault {
                return folder1.isDefault && !folder2.isDefault
            }
            return folder1.createdAt < folder2.createdAt
        }
    }
    
    func fetchDefaultFolder() throws -> RecordingFolder? {
        let descriptor = FetchDescriptor<RecordingFolder>(
            predicate: #Predicate<RecordingFolder> { folder in
                folder.isDefault == true
            }
        )
        return try context.fetch(descriptor).first
    }
    
    func deleteFolder(_ folder: RecordingFolder) throws {
        context.delete(folder)
        try context.save()
    }
    
    func updateFolder(_ folder: RecordingFolder) throws {
        try context.save()
    }
    
    // MARK: - Recording Operations with Folders
    
    func saveRecording(_ recording: Recording, to folder: RecordingFolder? = nil) throws {
        if let folder = folder {
            recording.folder = folder
        } else {
            // Assign to default folder if no folder specified
            let defaultFolder = try fetchDefaultFolder()
            recording.folder = defaultFolder
        }
        
        context.insert(recording)
        try context.save()
    }
    
    func fetchRecordings(in folder: RecordingFolder) throws -> [Recording] {
        // Fetch all recordings first, then filter
        let descriptor = FetchDescriptor<Recording>()
        let allRecordings = try context.fetch(descriptor)
        
        // Filter recordings that belong to this folder and sort by creation date
        return allRecordings.filter { recording in
            recording.folder?.id == folder.id
        }.sorted { $0.createdAt > $1.createdAt }
    }
    
    func fetchAllRecordings() throws -> [Recording] {
        let descriptor = FetchDescriptor<Recording>()
        let recordings = try context.fetch(descriptor)
        return recordings.sorted { $0.createdAt > $1.createdAt }
    }
    
    func moveRecording(_ recording: Recording, to folder: RecordingFolder) throws {
        recording.folder = folder
        try context.save()
    }
    
    func deleteRecording(_ recording: Recording) throws {
        context.delete(recording)
        try context.save()
    }
    
    // MARK: - Utilities
    
    func createDefaultFolderIfNeeded() throws -> RecordingFolder {
        if let existing = try fetchDefaultFolder() {
            return existing
        }
        
        let defaultFolder = RecordingFolder(
            name: "My Recordings",
            colorName: "blue",
            isDefault: true
        )
        
        try saveFolder(defaultFolder)
        return defaultFolder
    }
    
    func getRecentFolders(limit: Int = 3) throws -> [RecordingFolder] {
        let allFolders = try fetchFolders()
        let foldersWithRecordings = allFolders.filter { !$0.recordings.isEmpty }
        
        return Array(foldersWithRecordings
            .sorted { folder1, folder2 in
                guard let date1 = folder1.latestRecordingDate,
                      let date2 = folder2.latestRecordingDate else {
                    return folder1.latestRecordingDate != nil
                }
                return date1 > date2
            }
            .prefix(limit))
    }
}
