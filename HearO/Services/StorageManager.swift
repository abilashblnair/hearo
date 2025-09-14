import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Comprehensive storage management service for HearO app
@MainActor
final class StorageManager: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = StorageManager()
    
    // MARK: - Published Properties
    @Published var isProcessing = false
    @Published var operationProgress: Double = 0.0
    @Published var operationStatus: String = ""
    
    // MARK: - Private Properties
    private let context: ModelContext
    private let folderStore: FolderDataStore
    private let recordingStore: RecordingDataStore
    
    // MARK: - Initialization
    private init() {
        self.context = LocalDataManager.shared.modelContainer.mainContext
        self.folderStore = FolderDataStore(context: context)
        self.recordingStore = RecordingDataStore(context: context)
    }
    
    // MARK: - Storage Operations
    
    /// Cleans up empty folders (excludes default folder)
    func cleanEmptyFolders() async throws -> StorageCleanupResult {
        isProcessing = true
        operationStatus = "Finding empty folders..."
        operationProgress = 0.1
        
        defer {
            isProcessing = false
            operationProgress = 0.0
            operationStatus = ""
        }
        
        do {
            let allFolders = try folderStore.fetchFolders()
            let emptyFolders = allFolders.filter { !$0.isDefault && $0.recordings.isEmpty }
            
            operationStatus = "Cleaning \(emptyFolders.count) empty folders..."
            operationProgress = 0.5
            
            var deletedCount = 0
            for folder in emptyFolders {
                try folderStore.deleteFolder(folder)
                deletedCount += 1
            }
            
            operationProgress = 1.0
            return StorageCleanupResult(
                deletedFoldersCount: deletedCount,
                message: deletedCount > 0 ? 
                    "Successfully cleaned \(deletedCount) empty folder\(deletedCount == 1 ? "" : "s")" :
                    "No empty folders found to clean"
            )
        } catch {
            throw StorageError.cleanupFailed("Failed to clean empty folders: \(error.localizedDescription)")
        }
    }
    
    /// Exports all app data to a shareable format
    func exportAllData() async throws -> StorageExportResult {
        isProcessing = true
        operationStatus = "Preparing export..."
        operationProgress = 0.1
        
        defer {
            isProcessing = false
            operationProgress = 0.0
            operationStatus = ""
        }
        
        do {
            // Create export directory
            let exportURL = try createExportDirectory()
            
            operationStatus = "Gathering recordings and folders..."
            operationProgress = 0.2
            
            let allRecordings = try recordingStore.fetchRecordings()
            let allFolders = try folderStore.fetchFolders()
            
            operationStatus = "Exporting metadata..."
            operationProgress = 0.3
            
            // Export metadata as JSON
            let metadata = try await createExportMetadata(recordings: allRecordings, folders: allFolders)
            let metadataURL = exportURL.appendingPathComponent("metadata.json")
            let metadataData = try JSONEncoder().encode(metadata)
            try metadataData.write(to: metadataURL)
            
            operationStatus = "Copying audio files..."
            operationProgress = 0.4
            
            // Export audio files
            let audioExportURL = exportURL.appendingPathComponent("audio")
            try FileManager.default.createDirectory(at: audioExportURL, withIntermediateDirectories: true)
            
            var exportedAudioCount = 0
            let totalRecordings = allRecordings.count
            
            for (index, recording) in allRecordings.enumerated() {
                operationProgress = 0.4 + (0.5 * Double(index) / Double(totalRecordings))
                
                if let audioFileURL = getAudioFileURL(for: recording) {
                    let exportAudioURL = audioExportURL.appendingPathComponent("\(recording.id.uuidString).m4a")
                    try FileManager.default.copyItem(at: audioFileURL, to: exportAudioURL)
                    exportedAudioCount += 1
                }
            }
            
            operationStatus = "Creating archive..."
            operationProgress = 0.9
            
            // Create zip archive
            let archiveURL = try await createZipArchive(from: exportURL)
            
            // Clean up temporary export directory
            try FileManager.default.removeItem(at: exportURL)
            
            operationProgress = 1.0
            
            return StorageExportResult(
                exportURL: archiveURL,
                recordingsCount: allRecordings.count,
                foldersCount: allFolders.count,
                audioFilesCount: exportedAudioCount,
                fileSize: try getFileSize(at: archiveURL)
            )
            
        } catch {
            throw StorageError.exportFailed("Failed to export data: \(error.localizedDescription)")
        }
    }
    
    /// Clears all app data (with confirmation)
    func clearAllData() async throws -> StorageClearResult {
        isProcessing = true
        operationStatus = "Clearing all data..."
        operationProgress = 0.1
        
        defer {
            isProcessing = false
            operationProgress = 0.0
            operationStatus = ""
        }
        
        do {
            operationStatus = "Gathering data to clear..."
            operationProgress = 0.2
            
            let allRecordings = try recordingStore.fetchRecordings()
            let allFolders = try folderStore.fetchFolders()
            
            operationStatus = "Deleting audio files..."
            operationProgress = 0.3
            
            // Delete all audio files
            var deletedAudioCount = 0
            for recording in allRecordings {
                if let audioFileURL = getAudioFileURL(for: recording) {
                    try? FileManager.default.removeItem(at: audioFileURL)
                    deletedAudioCount += 1
                }
            }
            
            operationStatus = "Clearing database records..."
            operationProgress = 0.6
            
            // Delete all recordings
            for recording in allRecordings {
                try recordingStore.deleteRecording(recording)
            }
            
            operationStatus = "Clearing folders..."
            operationProgress = 0.8
            
            // Delete all non-default folders
            let nonDefaultFolders = allFolders.filter { !$0.isDefault }
            for folder in nonDefaultFolders {
                try folderStore.deleteFolder(folder)
            }
            
            operationStatus = "Recreating default folder..."
            operationProgress = 0.9
            
            // Ensure default folder exists and is clean
            let _ = try folderStore.createDefaultFolderIfNeeded()
            
            operationProgress = 1.0
            
            return StorageClearResult(
                deletedRecordingsCount: allRecordings.count,
                deletedFoldersCount: nonDefaultFolders.count,
                deletedAudioFilesCount: deletedAudioCount,
                message: "Successfully cleared all data"
            )
            
        } catch {
            throw StorageError.clearFailed("Failed to clear data: \(error.localizedDescription)")
        }
    }
    
    /// Gets storage statistics
    func getStorageStats() async throws -> StorageStats {
        do {
            let allRecordings = try recordingStore.fetchRecordings()
            let allFolders = try folderStore.fetchFolders()
            
            let totalDuration = allRecordings.reduce(0) { $0 + $1.duration }
            let audioFileSize = await calculateAudioFilesSize(recordings: allRecordings)
            let emptyFoldersCount = allFolders.filter { !$0.isDefault && $0.recordings.isEmpty }.count
            
            return StorageStats(
                totalRecordings: allRecordings.count,
                totalFolders: allFolders.count,
                emptyFolders: emptyFoldersCount,
                totalDuration: totalDuration,
                totalAudioFileSize: audioFileSize
            )
        } catch {
            throw StorageError.statsFailed("Failed to get storage stats: \(error.localizedDescription)")
        }
    }
}

// MARK: - Private Helper Methods
private extension StorageManager {
    
    func createExportDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let exportDir = tempDir.appendingPathComponent("HearO_Export_\(Date().timeIntervalSince1970)")
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        return exportDir
    }
    
    func createExportMetadata(recordings: [Recording], folders: [RecordingFolder]) async throws -> ExportMetadata {
        let recordingData = recordings.map { recording in
            ExportRecording(
                id: recording.id.uuidString,
                title: recording.title,
                createdAt: recording.createdAt,
                duration: recording.duration,
                notes: recording.notes,
                transcriptText: recording.transcriptText,
                transcriptLanguage: recording.transcriptLanguage,
                summaryText: recording.getCachedSummary()?.overview,
                summaryLanguage: recording.summaryLanguage,
                folderID: recording.folder?.id.uuidString
            )
        }
        
        let folderData = folders.map { folder in
            ExportFolder(
                id: folder.id.uuidString,
                name: folder.name,
                colorName: folder.colorName,
                createdAt: folder.createdAt,
                isDefault: folder.isDefault
            )
        }
        
        return ExportMetadata(
            exportDate: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            recordings: recordingData,
            folders: folderData
        )
    }
    
    func createZipArchive(from sourceURL: URL) async throws -> URL {
        // For now, return the source directory instead of creating a zip
        // The user can manually compress it using share sheet
        // TODO: Implement proper zip creation using Compression framework
        
        return sourceURL
    }
    
    func getAudioFileURL(for recording: Recording) -> URL? {
        do {
            let audioURL = try AudioFileStore.url(for: recording.id)
            return FileManager.default.fileExists(atPath: audioURL.path) ? audioURL : nil
        } catch {
            return nil
        }
    }
    
    func getFileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    func calculateAudioFilesSize(recordings: [Recording]) async -> Int64 {
        var totalSize: Int64 = 0
        for recording in recordings {
            if let audioURL = getAudioFileURL(for: recording) {
                totalSize += (try? getFileSize(at: audioURL)) ?? 0
            }
        }
        return totalSize
    }
}

// MARK: - Supporting Data Models

struct StorageCleanupResult {
    let deletedFoldersCount: Int
    let message: String
}

struct StorageExportResult {
    let exportURL: URL
    let recordingsCount: Int
    let foldersCount: Int
    let audioFilesCount: Int
    let fileSize: Int64
    
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

struct StorageClearResult {
    let deletedRecordingsCount: Int
    let deletedFoldersCount: Int
    let deletedAudioFilesCount: Int
    let message: String
}

struct StorageStats {
    let totalRecordings: Int
    let totalFolders: Int
    let emptyFolders: Int
    let totalDuration: TimeInterval
    let totalAudioFileSize: Int64
    
    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: totalDuration) ?? "0s"
    }
    
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: totalAudioFileSize, countStyle: .file)
    }
}

struct ExportMetadata: Codable {
    let exportDate: Date
    let appVersion: String
    let recordings: [ExportRecording]
    let folders: [ExportFolder]
}

struct ExportRecording: Codable {
    let id: String
    let title: String
    let createdAt: Date
    let duration: TimeInterval
    let notes: String?
    let transcriptText: String?
    let transcriptLanguage: String?
    let summaryText: String?
    let summaryLanguage: String?
    let folderID: String?
}

struct ExportFolder: Codable {
    let id: String
    let name: String
    let colorName: String
    let createdAt: Date
    let isDefault: Bool
}

enum StorageError: LocalizedError {
    case cleanupFailed(String)
    case exportFailed(String)
    case clearFailed(String)
    case statsFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .cleanupFailed(let message):
            return "Cleanup failed: \(message)"
        case .exportFailed(let message):
            return "Export failed: \(message)"
        case .clearFailed(let message):
            return "Clear failed: \(message)"
        case .statsFailed(let message):
            return "Stats failed: \(message)"
        }
    }
}

// MARK: - DateFormatter Extension
private extension DateFormatter {
    static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}
