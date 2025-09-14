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
        // Don't deactivate if recording is active
        guard !isRecording else { return }
        
        // Don't deactivate if there's a paused recording session that can be resumed
        guard !audioSessionManager.isSessionActive else { return }
        
        // Only deactivate if there's truly no active session
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
    
    func enableTranscriptionDuringRecording() async throws {
        try await audioSessionManager.requestSpeechPermission()
        try audioSessionManager.enableTranscriptionDuringRecording()
    }
    
    func disableTranscription() {
        audioSessionManager.stopTranscription()
    }
    
    func forceRestartSpeechRecognition() {
        audioSessionManager.forceRestartSpeechRecognition()
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
    
    // MARK: - Interruption Recovery
    
    /// Manually attempt to resume recording after an interruption (like a phone call)
    func manualResumeAfterInterruption() {
        audioSessionManager.manualResumeAfterInterruption()
    }
    
    /// Check if there are operations waiting to resume after an interruption
    var hasPendingResumeOperations: Bool {
        audioSessionManager.hasPendingResumeOperations
    }
    
    /// Configure how interruptions are handled
    func configureInterruptionHandling(
        pauseOnInterruption: Bool = true,
        autoResumeAfterInterruption: Bool = true,
        maxAutoResumeAttempts: Int = 3
    ) {
        audioSessionManager.configureInterruptionHandling(
            pauseOnInterruption: pauseOnInterruption,
            autoResumeAfterInterruption: autoResumeAfterInterruption,
            maxAutoResumeAttempts: maxAutoResumeAttempts
        )
    }
    
    /// Disable automatic resume for current interruption
    func disableAutoResumeForCurrentInterruption() {
        audioSessionManager.disableAutoResumeForCurrentInterruption()
    }
    
    /// Force resume even if auto-resume was disabled
    func forceResumeAfterInterruption() {
        audioSessionManager.forceResumeAfterInterruption()
    }
    
    // MARK: - Interruption Callbacks
    
    var onInterruptionBegan: (() -> Void)? {
        get { audioSessionManager.onInterruptionBegan }
        set { audioSessionManager.onInterruptionBegan = newValue }
    }
    
    var onRecordingPaused: (() -> Void)? {
        get { audioSessionManager.onRecordingPaused }
        set { audioSessionManager.onRecordingPaused = newValue }
    }
    
    var onRecordingResumed: (() -> Void)? {
        get { audioSessionManager.onRecordingResumed }
        set { audioSessionManager.onRecordingResumed = newValue }
    }
    
    var onAutoResumeAttemptFailed: ((Int, Error) -> Void)? {
        get { audioSessionManager.onAutoResumeAttemptFailed }
        set { audioSessionManager.onAutoResumeAttemptFailed = newValue }
    }
    
    var onTranscriptCacheRestored: (([String], String) -> Void)? {
        get { audioSessionManager.onTranscriptCacheRestored }
        set { audioSessionManager.onTranscriptCacheRestored = newValue }
    }
    
    // MARK: - Interruption State Inspection
    
    /// Check if recording was active before the interruption
    var wasRecordingActiveBeforeInterruption: Bool {
        audioSessionManager.wasRecordingActiveBeforeInterruption
    }
    
    /// Check if transcription was active before the interruption
    var wasTranscriptionActiveBeforeInterruption: Bool {
        audioSessionManager.wasTranscriptionActiveBeforeInterruption
    }
    
    // MARK: - Transcript Caching
    
    /// Get cached transcript data
    func getCachedTranscript() -> (lines: [String], partial: String) {
        return audioSessionManager.getCachedTranscript()
    }
    
    /// Manually cache transcript data from UI
    func cacheTranscript(lines: [String], partial: String) {
        audioSessionManager.cacheTranscript(lines: lines, partial: partial)
    }
}
