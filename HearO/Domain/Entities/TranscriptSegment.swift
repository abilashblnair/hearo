import Foundation

struct TranscriptSegment: Identifiable, Hashable, Codable {
    let id: UUID
    var speaker: String?
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
}
