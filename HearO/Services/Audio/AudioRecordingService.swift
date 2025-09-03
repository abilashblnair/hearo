import Foundation

protocol AudioRecordingService {
    func requestMicPermission() async throws
    func startRecording(to url: URL) throws
    func startRecordingWithNativeTranscription(to url: URL) async throws
    func pauseRecording() throws
    func resumeRecording() throws
    func stopRecording() throws -> TimeInterval
    var isRecording: Bool { get }
    var currentPower: Float { get } // -160...0 dB for waveform metering
    func updateMeters()
    // New session state for mini recorder controls
    var currentRecordingURL: URL? { get }
    var currentTime: TimeInterval { get }
    var isSessionActive: Bool { get }
    // Session management
    func deactivateSessionIfNeeded()
    // Transcription support
    var onTranscriptUpdate: ((String, Bool) -> Void)? { get set }
    // Interruption recovery
    func manualResumeAfterInterruption()
    var hasPendingResumeOperations: Bool { get }
}
