import Foundation
import SwiftData

protocol FolderRepository {
    func fetchAllFolders() async throws -> [RecordingFolder]
    func fetchDefaultFolder() async throws -> RecordingFolder?
    func createFolder(name: String, colorName: String, isDefault: Bool) async throws -> RecordingFolder
    func updateFolder(_ folder: RecordingFolder) async throws
    func deleteFolder(_ folder: RecordingFolder) async throws
    func fetchRecordings(in folder: RecordingFolder) async throws -> [Recording]
    func moveRecording(_ recording: Recording, to folder: RecordingFolder) async throws
    func getRecentFolders(limit: Int) async throws -> [RecordingFolder]
}

final class LocalFolderRepository: FolderRepository {
    private let context: ModelContext
    
    init(context: ModelContext) {
        self.context = context
    }
    
    func fetchAllFolders() async throws -> [RecordingFolder] {
        let descriptor = FetchDescriptor<RecordingFolder>()
        let folders = try context.fetch(descriptor)
        return folders.sorted { $0.createdAt < $1.createdAt }
    }
    
    func fetchDefaultFolder() async throws -> RecordingFolder? {
        let descriptor = FetchDescriptor<RecordingFolder>()
        let folders = try context.fetch(descriptor)
        return folders.first { $0.isDefault }
    }
    
    func createFolder(name: String, colorName: String, isDefault: Bool = false) async throws -> RecordingFolder {
        let folder = RecordingFolder(name: name, colorName: colorName, isDefault: isDefault)
        context.insert(folder)
        try context.save()
        return folder
    }
    
    func updateFolder(_ folder: RecordingFolder) async throws {
        try context.save()
    }
    
    func deleteFolder(_ folder: RecordingFolder) async throws {
        // Move recordings to default folder before deleting
        if !folder.isDefault {
            let defaultFolder = try await fetchDefaultFolder()
            if let defaultFolder = defaultFolder {
                for recording in folder.recordings {
                    recording.folder = defaultFolder
                }
            }
        }
        
        context.delete(folder)
        try context.save()
    }
    
    func fetchRecordings(in folder: RecordingFolder) async throws -> [Recording] {
        let descriptor = FetchDescriptor<Recording>()
        let allRecordings = try context.fetch(descriptor)
        
        // Filter recordings that belong to this folder and sort by creation date
        return allRecordings.filter { recording in
            recording.folder?.id == folder.id
        }.sorted { $0.createdAt > $1.createdAt }
    }
    
    func moveRecording(_ recording: Recording, to folder: RecordingFolder) async throws {
        recording.folder = folder
        try context.save()
    }
    
    func getRecentFolders(limit: Int = 5) async throws -> [RecordingFolder] {
        // Get folders sorted by their latest recording date
        let allFolders = try await fetchAllFolders()
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
