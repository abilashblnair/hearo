import Foundation
import AVFoundation

/// Recording service implementation using the unified audio session manager
final class UnifiedAudioRecordingServiceImpl: AudioRecordingService {
    private let audioSessionManager = AudioSessionManager.shared
    
    // MARK: - Transcription Callbacks
    var onTranscriptUpdate: ((String, Bool) -> Void)? {
        get { audioSessionManager.onTranscriptUpdate }
        set { audioSessionManager.onTranscriptUpdate = newValue }
    }
    
    // MARK: - AudioRecordingService Implementation
    
    func requestMicPermission() async throws {
        try await audioSessionManager.requestPermissions()
    }
    
    func startRecording(to url: URL) throws {
        guard AudioStateManager.shared.startRecording() else {
            throw NSError(domain: "AudioConflict", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot start recording: Audio conflict detected"])
        }
        try audioSessionManager.startRecording(to: url)
    }
    
    func startRecordingWithNativeTranscription(to url: URL) async throws {
        guard AudioStateManager.shared.startRecording() else {
            throw NSError(domain: "AudioConflict", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot start recording: Audio conflict detected"])
        }
        try await audioSessionManager.startRecordingWithNativeTranscription(to: url)
    }
    
    func pauseRecording() throws {
        try audioSessionManager.pauseRecording()
    }
    
    func resumeRecording() throws {
        try audioSessionManager.resumeRecording()
    }
    
    func stopRecording() throws -> TimeInterval {
        let duration = try audioSessionManager.stopRecording()
        AudioStateManager.shared.stopRecording()
        return duration
    }
    
    var isRecording: Bool {
        audioSessionManager.isRecording
    }
    
    var currentPower: Float {
        audioSessionManager.averagePower
    }
    
    func updateMeters() {
        // Power updates are handled automatically by AudioSessionManager
        // This method is kept for compatibility but does nothing
    }
    
    var currentRecordingURL: URL? {
        audioSessionManager.currentRecordingURL
    }
    
    var currentTime: TimeInterval {
        audioSessionManager.currentTime
    }
    
    var isSessionActive: Bool {
        audioSessionManager.isSessionActive
    }
    
    func deactivateSessionIfNeeded() {
        guard !isRecording else { return }
        audioSessionManager.deactivateSession()
    }
    
    // MARK: - Transcription Support
    
    func requestSpeechPermission() async throws {
        try await audioSessionManager.requestSpeechPermission()
    }
    
    func enableTranscription() async throws {
        try await audioSessionManager.requestSpeechPermission()
        try audioSessionManager.startTranscription()
    }
    
    func disableTranscription() {
        print("🔇 UnifiedAudioRecordingServiceImpl: Disabling transcription...")
        audioSessionManager.stopTranscription()
    }
    
    // MARK: - Power Level Updates
    
    var onPowerUpdate: ((Float) -> Void)? {
        get { audioSessionManager.onPowerUpdate }
        set { audioSessionManager.onPowerUpdate = newValue }
    }
    
    var onError: ((Error) -> Void)? {
        get { audioSessionManager.onError }
        set { audioSessionManager.onError = newValue }
    }
    
    var isTranscriptionActive: Bool {
        audioSessionManager.isTranscriptionActive
    }
}
