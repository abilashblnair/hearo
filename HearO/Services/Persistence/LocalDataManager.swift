import Foundation
import SwiftData
import Combine

final class LocalDataManager {
    static let shared = LocalDataManager()
    let modelContainer: ModelContainer
    
    private var subscriptionCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

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
            // Clean up old recordings for free users
            await performRecordingCleanupIfNeeded()
        }
        
        // Set up periodic cleanup and subscription monitoring
        setupPeriodicCleanup()
        
        // Monitor subscription changes on main actor
        Task { @MainActor in
            await monitorSubscriptionChanges()
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
    
    // MARK: - Cleanup Scheduling
    
    private func setupPeriodicCleanup() {
        // Schedule daily cleanup at 3 AM
        let calendar = Calendar.current
        let now = Date()
        
        // Find the next 3 AM
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 3
        components.minute = 0
        components.second = 0
        
        guard var nextCleanup = calendar.date(from: components) else { return }
        
        // If 3 AM has already passed today, schedule for tomorrow
        if nextCleanup <= now {
            nextCleanup = calendar.date(byAdding: .day, value: 1, to: nextCleanup) ?? nextCleanup
        }
        
        print("📅 Scheduled next recording cleanup for: \(nextCleanup)")
        
        // Create repeating timer for daily cleanup
        let timer = Timer(fire: nextCleanup, interval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performRecordingCleanupIfNeeded()
            }
        }
        
        RunLoop.main.add(timer, forMode: .common)
    }
    
    @MainActor
    private func monitorSubscriptionChanges() async {
        // Monitor subscription changes and trigger cleanup if user downgrades from premium
        subscriptionCancellable = SubscriptionService.shared.$isPremium
            .removeDuplicates()
            .sink { [weak self] isPremium in
                // If user lost premium access, trigger cleanup
                if !isPremium {
                    Task { @MainActor [weak self] in
                        print("📉 User lost premium access - triggering recording cleanup")
                        await self?.performRecordingCleanupIfNeeded()
                    }
                }
            }
        
        // Also listen for explicit subscription downgrade notifications
        NotificationCenter.default.publisher(for: .subscriptionDowngrade)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    print("🔄 Received subscription downgrade notification - performing cleanup")
                    await self?.performRecordingCleanupIfNeeded()
                    await self?.performFeatureDowngrade()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Recording Cleanup
    
    @MainActor
    private func performRecordingCleanupIfNeeded() async {
        // Only perform cleanup for free users
        guard !SubscriptionService.shared.isPremium else {
            print("💎 User is premium - skipping recording cleanup")
            return
        }
        
        do {
            let recordingStore = RecordingDataStore(context: modelContainer.mainContext)
            let allRecordings = try recordingStore.fetchRecordings()
            
            // Get recordings that should be deleted based on retention policy
            let featureManager = FeatureManager.shared
            let recordingsToDelete = allRecordings.filter { recording in
                !featureManager.shouldRetainRecording(date: recording.createdAt)
            }
            
            guard !recordingsToDelete.isEmpty else {
                print("🧹 No old recordings to clean up")
                return
            }
            
            print("🧹 Cleaning up \(recordingsToDelete.count) recordings older than 7 days for free user")
            
            // Delete each recording
            for recording in recordingsToDelete {
                await deleteRecordingSafely(recording, using: recordingStore)
            }
            
            // Save changes
            try modelContainer.mainContext.save()
            
            print("✅ Successfully cleaned up \(recordingsToDelete.count) old recordings")
            
        } catch {
            print("❌ Failed to perform recording cleanup: \(error)")
        }
    }
    
    @MainActor
    private func deleteRecordingSafely(_ recording: Recording, using recordingStore: RecordingDataStore) async {
        do {
            // Delete audio file first
            let audioURL = recording.finalAudioURL()
            if FileManager.default.fileExists(atPath: audioURL.path) {
                try FileManager.default.removeItem(at: audioURL)
                print("🗂️ Deleted audio file: \(audioURL.lastPathComponent)")
            }
            
            // Delete from database
            try recordingStore.deleteRecording(recording)
            print("📝 Deleted recording from database: \(recording.title)")
            
        } catch {
            print("❌ Failed to delete recording '\(recording.title)': \(error)")
        }
    }
    
    // MARK: - Public Cleanup Methods
    
    /// Manually trigger cleanup for testing or when subscription status changes
    @MainActor
    public func triggerRecordingCleanup() async {
        await performRecordingCleanupIfNeeded()
    }
    
    /// Get count of recordings that would be deleted for free users
    @MainActor
    public func getRecordingsToDeleteCount() async throws -> Int {
        guard !SubscriptionService.shared.isPremium else {
            return 0
        }
        
        let recordingStore = RecordingDataStore(context: modelContainer.mainContext)
        let allRecordings = try recordingStore.fetchRecordings()
        
        let featureManager = FeatureManager.shared
        return allRecordings.filter { recording in
            !featureManager.shouldRetainRecording(date: recording.createdAt)
        }.count
    }
    
    // MARK: - Feature Downgrade
    
    @MainActor
    private func performFeatureDowngrade() async {
        print("⬇️ Performing feature downgrade for subscription loss")
        
        // Reset any premium-specific settings to default values
        let userDefaults = UserDefaults.standard
        
        // Reset FeatureManager counters if needed
        FeatureManager.shared.objectWillChange.send()
        
        // Clean up any premium-only data
        await performRecordingCleanupIfNeeded()
        
        // Post notification to update all UI immediately
        NotificationCenter.default.post(
            name: .subscriptionStatusChanged,
            object: nil,
            userInfo: ["isPremium": false, "forceUIUpdate": true]
        )
        
        print("✅ Feature downgrade completed")
    }
}
