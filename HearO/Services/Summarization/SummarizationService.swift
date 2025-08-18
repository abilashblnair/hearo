import Foundation

protocol SummarizationService {
    func summarize(segments: [TranscriptSegment], locale: String) async throws -> Summary
}

protocol TranslationService {
    func translate(segments: [TranscriptSegment], targetLanguage: String) async throws -> [TranscriptSegment]
}
