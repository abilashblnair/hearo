import Foundation

final class WhisperTranscriptionServiceImpl: TranscriptionService {
    func transcribe(audioURL: URL, languageCode: String) async throws -> [TranscriptSegment] {
        // MVP stub: Replace with real Whisper/AssemblyAI API call
        // For now, just return a fake transcript segment after a delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        return [
            TranscriptSegment(
                id: UUID(),
                speaker: "Speaker 1",
                text: "[Stub Transcript for \(audioURL.lastPathComponent)]",
                startTime: 0,
                endTime: 10
            )
        ]
    }
}
