import Foundation

protocol TranscriptionService {
    func transcribe(audioURL: URL, languageCode: String) async throws -> [TranscriptSegment]
}
