import Foundation
import AVFoundation

final class AVAudioRecordingServiceImpl: NSObject, AudioRecordingService, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private(set) var isRecording: Bool = false
    private(set) var currentPower: Float = -160
    private var meterTimer: Timer?

    // New: expose session state
    var currentRecordingURL: URL? { recorder?.url }
    var currentTime: TimeInterval { recorder?.currentTime ?? 0 }
    var isSessionActive: Bool { recorder != nil }

    func requestMicPermission() async throws {
        if #available(iOS 17.0, *) {
            try await withCheckedThrowingContinuation { cont in
                AVAudioApplication.requestRecordPermission { granted in
                    if granted { cont.resume() } else {
                        cont.resume(throwing: NSError(domain: "MicPermission", code: 1))
                    }
                }
            }
        } else {
            try await withCheckedThrowingContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    if granted { cont.resume() } else {
                        cont.resume(throwing: NSError(domain: "MicPermission", code: 1))
                    }
                }
            }
        }
    }

    func startRecording(to url: URL) throws {
        let session = AVAudioSession.sharedInstance()
        
        // Simple, conflict-free audio session setup
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        // Simple, standard recording settings
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.delegate = self
        recorder?.isMeteringEnabled = true
        guard recorder?.record() == true else { throw NSError(domain: "Record", code: 2) }
        isRecording = true
        startMetering()
    }

    func pauseRecording() throws {
        guard let recorder, isRecording else { return }
        recorder.pause()
        isRecording = false
        stopMetering()
    }

    func resumeRecording() throws {
        guard let recorder, !isRecording else { return }
        if recorder.record() {
            isRecording = true
            startMetering()
        } else {
            throw NSError(domain: "Record", code: 3)
        }
    }

    func stopRecording() throws -> TimeInterval {
        stopMetering()
        recorder?.stop()
        let dur = recorder?.currentTime ?? 0
        isRecording = false
        
        // Clean up audio session properly
        try? AVAudioSession.sharedInstance().setActive(false)
        recorder = nil
        return dur
    }

    private func startMetering() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.recorder?.updateMeters()
            self?.currentPower = self?.recorder?.averagePower(forChannel: 0) ?? -160
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    func updateMeters() {
        recorder?.updateMeters()
        currentPower = recorder?.averagePower(forChannel: 0) ?? -160
    }

    // Add method to safely deactivate session when all audio work is done
    func deactivateSessionIfNeeded() {
        // Don't deactivate if there's an active recorder or recording in progress
        guard recorder == nil && !isRecording else { return }
        
        // Don't deactivate if there's a paused recording session that can be resumed
        // In the legacy service, if recorder exists but isn't recording, it might be paused
        guard !isSessionActive else { return }
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
        }
    }

    // MARK: - New Protocol Methods (Not implemented in legacy service)
    
    func startRecordingWithNativeTranscription(to url: URL) async throws {
        throw NSError(domain: "NotSupported", code: 1, userInfo: [NSLocalizedDescriptionKey: "Native transcription not supported in legacy service. Use UnifiedAudioRecordingServiceImpl."])
    }
    
    var onTranscriptUpdate: ((String, Bool) -> Void)? {
        get { nil }
        set { 
            if newValue != nil {
            }
        }
    }
    
    // MARK: - Interruption Recovery (Not implemented in legacy service)
    
    /// Manual resume not supported in legacy service - use UnifiedAudioRecordingServiceImpl for full functionality
    func manualResumeAfterInterruption() {
    }
    
    /// Pending resume operations not tracked in legacy service
    var hasPendingResumeOperations: Bool {
        return false // Legacy service doesn't track pending operations
    }
    
    // MARK: - AVAudioRecorderDelegate
    
    // Optional: handle interruptions
    func audioRecorderBeginInterruption(_ recorder: AVAudioRecorder) {
        stopMetering()
        isRecording = false
    }
    
    func audioRecorderEndInterruption(_ recorder: AVAudioRecorder, withOptions flags: Int) {
        // Basic resume logic for AVAudioRecorder
        if flags == 1 { // AVAudioSessionInterruptionOptions.shouldResume
            do {
                try resumeRecording()
            } catch {
            }
        }
    }
}
