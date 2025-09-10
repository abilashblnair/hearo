import Foundation
import SwiftData

final class LocalDataManager {
    static let shared = LocalDataManager()
    let modelContainer: ModelContainer

    private init() {
        let schema = Schema([
            Recording.self,
            RecordingFolder.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        self.modelContainer = try! ModelContainer(for: schema, configurations: [config])

        Task {
            // Ensure default folder exists
            await setupDefaultFolder()
        }
    }
    
    @MainActor
    private func setupDefaultFolder() {
        let context = modelContainer.mainContext
        let folderStore = FolderDataStore(context: context)
        
        do {
            // Create default folder if it doesn't exist
            let _ = try folderStore.createDefaultFolderIfNeeded()
            
            // Migrate existing recordings to default folder
            try migrateExistingRecordings(folderStore: folderStore)
        } catch {
        }
    }
    
    @MainActor
    private func migrateExistingRecordings(folderStore: FolderDataStore) throws {
        let recordings = try folderStore.fetchAllRecordings()
        let recordingsWithoutFolder = recordings.filter { $0.folder == nil }
        
        if !recordingsWithoutFolder.isEmpty {
            let defaultFolder = try folderStore.fetchDefaultFolder()
            
            for recording in recordingsWithoutFolder {
                recording.folder = defaultFolder
            }
            
            try modelContainer.mainContext.save()
        }
    }
}
