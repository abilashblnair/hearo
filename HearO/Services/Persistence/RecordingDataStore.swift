import Foundation
import SwiftData

@Model
final class Recording: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    // Stores path to audio file. Prefer a relative path under Documents (e.g., "audio/<uuid>.m4a").
    var audioURL: String
    var duration: TimeInterval
    
    // User notes field
    var notes: String?
    
    // Folder relationship
    @Relationship var folder: RecordingFolder?
    
    // Transcript caching fields
    var transcriptText: String?
    var transcriptSegmentsData: Data? // JSON encoded TranscriptSegment array
    var transcriptLanguage: String?
    var transcriptCreatedAt: Date?
    
    // AI Summary caching fields
    var summaryData: Data? // JSON encoded Summary object
    var summaryCreatedAt: Date?
    var summaryLanguage: String?

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), audioURL: String, duration: TimeInterval, notes: String? = nil, folder: RecordingFolder? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.audioURL = audioURL
        self.duration = duration
        self.notes = notes
        self.folder = folder
        self.transcriptText = nil
        self.transcriptSegmentsData = nil
        self.transcriptLanguage = nil
        self.transcriptCreatedAt = nil
        self.summaryData = nil
        self.summaryCreatedAt = nil
        self.summaryLanguage = nil
    }

    func finalAudioURL() -> URL {
        // Use consistent Documents directory resolution
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("audio/\(id.uuidString).m4a")
        }
        
        var candidate: URL
        if let url = URL(string: audioURL), url.scheme == "file" { // file:// absolute
            candidate = url
        } else if audioURL.hasPrefix("/") { // absolute path
            candidate = URL(fileURLWithPath: audioURL)
        } else { // relative path under Documents
            candidate = docs.appendingPathComponent(audioURL)
        }
        
        
        // If candidate exists, return it
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        
        // Fallback: reconstruct from known scheme audio/<id>.m4a under Documents
        let fallback = docs.appendingPathComponent("audio/\(id.uuidString).m4a")
        
        // If fallback doesn't exist either, try to recover by searching for any file with this Recording's title
        if !FileManager.default.fileExists(atPath: fallback.path) {
            let audioDir = docs.appendingPathComponent("audio")
            
            if let files = try? FileManager.default.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil) {
                for _ in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                }
                
                // TODO: In the future, we could implement smart recovery by finding files
                // that match this Recording's creation date, size, or other metadata
            } else {
            }
        }
        
        return fallback
    }
    
    // MARK: - Transcript Caching Methods
    
    /// Check if this recording already has a cached transcript
    var hasTranscript: Bool {
        return transcriptText != nil && transcriptSegmentsData != nil
    }
    
    /// Get cached transcript segments
    func getCachedTranscriptSegments() -> [TranscriptSegment]? {
        guard let data = transcriptSegmentsData else { return nil }
        return try? JSONDecoder().decode([TranscriptSegment].self, from: data)
    }
    
    /// Cache transcript data
    func cacheTranscript(segments: [TranscriptSegment], language: String) {
        self.transcriptText = segments.map { $0.text }.joined(separator: "\n")
        self.transcriptSegmentsData = try? JSONEncoder().encode(segments)
        self.transcriptLanguage = language
        self.transcriptCreatedAt = Date()
    }
    
    // MARK: - Summary Caching Methods
    
    /// Check if this recording already has a cached summary
    var hasSummary: Bool {
        return summaryData != nil
    }
    
    /// Get cached summary
    func getCachedSummary() -> Summary? {
        guard let data = summaryData else { return nil }
        return try? JSONDecoder().decode(Summary.self, from: data)
    }
    
    /// Cache summary data
    func cacheSummary(_ summary: Summary, language: String) {
        self.summaryData = try? JSONEncoder().encode(summary)
        self.summaryCreatedAt = Date()
        self.summaryLanguage = language
    }
    
    /// Clear cached summary (for regeneration)
    func clearCachedSummary() {
        self.summaryData = nil
        self.summaryCreatedAt = nil
        self.summaryLanguage = nil
    }
}

final class RecordingDataStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func saveRecording(_ recording: Recording) throws {
        context.insert(recording)
        try context.save()
    }

    func fetchRecordings() throws -> [Recording] {
        let descriptor = FetchDescriptor<Recording>(sortBy: [SortDescriptor(\Recording.createdAt, order: .reverse)])
        return try context.fetch(descriptor)
    }

    func deleteRecording(_ recording: Recording) throws {
        context.delete(recording)
        try context.save()
    }
}
