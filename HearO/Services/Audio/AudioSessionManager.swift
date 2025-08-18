import Foundation
import AVFoundation
import Speech

/// Unified audio session manager that coordinates between recording and live transcription
final class AudioSessionManager: NSObject {
    
    // MARK: - Shared Instance
    static let shared = AudioSessionManager()
    
    // MARK: - Audio Components
    private let audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode { audioEngine.inputNode }
    private let audioSession = AVAudioSession.sharedInstance()
    
    // MARK: - Recording State
    private var isRecordingActive = false
    private var recordingURL: URL?
    private var audioFile: AVAudioFile?
    private var startTime: Date?
    private var currentPower: Float = -160
    private var meterTimer: Timer?
    
    // MARK: - Transcription State
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var transcriptionEnabled = false
    
    // MARK: - Callbacks
    var onTranscriptUpdate: ((String, Bool) -> Void)?
    var onPowerUpdate: ((Float) -> Void)?
    var onError: ((Error) -> Void)?
    
    // MARK: - Native Speech Recognition
    private var isNativeTranscriptionEnabled = false
    
    private override init() {
        super.init()
        setupNotifications()
    }
    
    // MARK: - Session Management
    
    func requestPermissions() async throws {
        // Request microphone permission
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
                audioSession.requestRecordPermission { granted in
                    if granted { cont.resume() } else {
                        cont.resume(throwing: NSError(domain: "MicPermission", code: 1))
                    }
                }
            }
        }
    }
    
    func requestSpeechPermission() async throws {
        try await withCheckedThrowingContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .authorized:
                    cont.resume()
                default:
                    cont.resume(throwing: NSError(domain: "SpeechPermission", code: 1))
                }
            }
        }
    }
    
    private func configureAudioSession() throws {
        // Use .playAndRecord to support both recording and transcription
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
        try audioSession.setPreferredSampleRate(44100.0)
        try audioSession.setPreferredInputNumberOfChannels(1)
        try audioSession.setPreferredIOBufferDuration(0.02)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    // MARK: - Recording Functions
    
    func startRecordingWithNativeTranscription(to url: URL) async throws {
        guard !isRecordingActive else { throw NSError(domain: "AudioSession", code: 1, userInfo: [NSLocalizedDescriptionKey: "Recording already active"]) }
        
        // Request speech permissions first
        try await requestSpeechPermission()
        
        // Start recording first
        try startRecording(to: url)
        
        // Then start transcription using the same audio engine
        try startTranscription()
        
        print("🎙️ AudioSessionManager: Recording with native transcription started")
    }
    
    func startRecording(to url: URL) throws {
        guard !isRecordingActive else { throw NSError(domain: "AudioSession", code: 1, userInfo: [NSLocalizedDescriptionKey: "Recording already active"]) }
        
        try configureAudioSession()
        
        recordingURL = url
        startTime = Date()
        
        // Ensure directory exists
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        // Configure audio format for recording
        let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)!
        
        // Create audio file for recording
        audioFile = try AVAudioFile(forWriting: url, settings: audioFormat.settings)
        
        // Remove any existing taps
        inputNode.removeTap(onBus: 0)
        
        // Install tap for both recording and transcription
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: audioFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // Write to audio file if recording
            if self.isRecordingActive, let audioFile = self.audioFile {
                try? audioFile.write(from: buffer)
            }
            
            // Send to speech recognition if enabled
            if self.transcriptionEnabled {
                self.recognitionRequest?.append(buffer)
            }
            
            // Update power levels for UI
            self.updatePowerLevel(from: buffer)
        }
        
        // Start audio engine if not already running
        if !audioEngine.isRunning {
            try audioEngine.start()
        }
        
        isRecordingActive = true
        startMetering()
        
        print("🎙️ AudioSessionManager: Recording started to \(url.lastPathComponent)")
    }
    
    func pauseRecording() throws {
        guard isRecordingActive else { return }
        isRecordingActive = false
        stopMetering()
        print("⏸️ AudioSessionManager: Recording paused")
    }
    
    func resumeRecording() throws {
        guard !isRecordingActive, audioFile != nil else { throw NSError(domain: "AudioSession", code: 2) }
        isRecordingActive = true
        startMetering()
        print("▶️ AudioSessionManager: Recording resumed")
    }
    
    func stopRecording() throws -> TimeInterval {
        guard let startTime = startTime else { throw NSError(domain: "AudioSession", code: 3) }
        
        isRecordingActive = false
        stopMetering()
        
        // Remove the shared audio tap
        inputNode.removeTap(onBus: 0)
        
        // Stop audio engine if no longer needed
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        audioFile = nil
        let duration = Date().timeIntervalSince(startTime)
        
        print("🛑 AudioSessionManager: Recording stopped, duration: \(String(format: "%.2f", duration))s")
        return duration
    }
    
    // MARK: - Transcription Functions
    
    func startTranscription() throws {
        guard !transcriptionEnabled else { return }
        
        // Initialize speech recognizer
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw NSError(domain: "SpeechRecognition", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer not available"])
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "SpeechRecognition", code: 2)
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false
        
        // Audio tap is already set up in startRecording method
        // The shared tap feeds audio to both recording and transcription
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    let isFinal = result.isFinal
                    self?.onTranscriptUpdate?(text, isFinal)
                }
                
                if let error = error {
                    print("Speech recognition error: \(error)")
                    self?.onError?(error)
                    
                    // Auto-restart for non-critical errors
                    if (error as NSError).code != 216 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            try? self?.startTranscription()
                        }
                    }
                }
            }
        }
        
        transcriptionEnabled = true
        print("🗣️ AudioSessionManager: Transcription started")
    }
    
    func stopTranscription() {
        guard transcriptionEnabled else { return }
        
        transcriptionEnabled = false
        
        // Don't remove audio tap - it's shared with recording
        // Tap will be removed when recording stops
        
        // Clean up speech recognition
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        speechRecognizer = nil
        
        print("🔇 AudioSessionManager: Transcription stopped")
    }
    
    // MARK: - Power Metering
    
    private func updatePowerLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0.0
        
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        
        let avgPower = sum / Float(frameLength)
        let dBValue = avgPower > 0 ? 20 * log10(sqrt(avgPower)) : -160
        
        currentPower = max(-160, min(0, dBValue))
        onPowerUpdate?(currentPower)
    }
    
    private func startMetering() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            // Power updates are handled in the audio tap callback
            // This timer ensures consistent updates even with low audio levels
            self?.onPowerUpdate?(self?.currentPower ?? -160)
        }
    }
    
    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }
    
    // MARK: - Session Cleanup
    
    func deactivateSession() {
        // Stop all operations
        if isRecordingActive {
            try? stopRecording()
        }
        
        stopTranscription()
        
        // Stop audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
            inputNode.removeTap(onBus: 0)
        }
        
        // Deactivate audio session
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        
        // Reset state
        recordingURL = nil
        audioFile = nil
        startTime = nil
        currentPower = -160
        
        print("🔊 AudioSessionManager: Session deactivated")
    }
    
    // MARK: - Public Properties
    
    var isRecording: Bool { isRecordingActive }
    var currentRecordingURL: URL? { recordingURL }
    var isSessionActive: Bool { audioEngine.isRunning || isRecordingActive }
    var averagePower: Float { currentPower }
    
    var currentTime: TimeInterval {
        guard let startTime = startTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: audioSession
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: audioSession
        )
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        switch type {
        case .began:
            if isRecordingActive {
                try? pauseRecording()
            }
            stopTranscription()
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    try? resumeRecording()
                    if transcriptionEnabled {
                        try? startTranscription()
                    }
                }
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        
        switch reason {
        case .oldDeviceUnavailable:
            // Handle device disconnect (e.g., headphones unplugged)
            if isRecordingActive {
                try? pauseRecording()
            }
        default:
            break
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        deactivateSession()
    }
}
