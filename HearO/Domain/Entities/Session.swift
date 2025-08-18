import Foundation

struct Session: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var createdAt: Date
    var audioURL: URL
    var duration: TimeInterval
    var languageCode: String
    var transcript: [TranscriptSegment]?
    var highlights: [HighlightItem]?
    var summary: Summary?
}
