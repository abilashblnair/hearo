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
    private var inputFormat: AVAudioFormat?
    private var recordingFormat: AVAudioFormat?
    
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
        print("🎤 Requesting microphone permissions...")
        
        // Request microphone permission
        if #available(iOS 17.0, *) {
            try await withCheckedThrowingContinuation { cont in
                AVAudioApplication.requestRecordPermission { granted in
                    print("🎤 AVAudioApplication permission result: \(granted)")
                    if granted { 
                        print("✅ Microphone permission granted")
                        cont.resume() 
                    } else {
                        print("❌ Microphone permission denied")
                        cont.resume(throwing: NSError(domain: "MicPermission", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied by user"]))
                    }
                }
            }
        } else {
            try await withCheckedThrowingContinuation { cont in
                audioSession.requestRecordPermission { granted in
                    print("🎤 AVAudioSession permission result: \(granted)")
                    if granted { 
                        print("✅ Microphone permission granted")
                        cont.resume() 
                    } else {
                        print("❌ Microphone permission denied")
                        cont.resume(throwing: NSError(domain: "MicPermission", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied by user"]))
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
        print("🔧 Configuring audio session with progressive fallback...")
        
        // Check current audio session state
        print("📊 Current audio session state:")
        print("  - Category: \(audioSession.category)")
        print("  - Other audio playing: \(audioSession.isOtherAudioPlaying)")
        print("  - Input available: \(audioSession.isInputAvailable)")
        print("  - Current sample rate: \(audioSession.sampleRate)")
        
        // Check microphone permission status
        let micPermission = AVAudioSession.sharedInstance().recordPermission
        print("  - Microphone permission: \(micPermission)")
        
        // Progressive configuration approach - try from most to least restrictive
        var configurationSuccess = false
        
        // Configuration 1: Full featured (most likely to fail in simulator)
        if !configurationSuccess {
            print("🔄 Trying Configuration 1: Full featured...")
            do {
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
                try audioSession.setPreferredSampleRate(44100.0)
                try audioSession.setPreferredInputNumberOfChannels(1)
                try audioSession.setPreferredIOBufferDuration(0.02)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                configurationSuccess = true
                print("✅ Configuration 1 successful!")
            } catch {
                print("❌ Configuration 1 failed: \(error)")
            }
        }
        
        // Configuration 2: Simplified options
        if !configurationSuccess {
            print("🔄 Trying Configuration 2: Simplified options...")
            do {
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [])
                try audioSession.setPreferredSampleRate(44100.0)
                try audioSession.setPreferredInputNumberOfChannels(1)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                configurationSuccess = true
                print("✅ Configuration 2 successful!")
            } catch {
                print("❌ Configuration 2 failed: \(error)")
            }
        }
        
        // Configuration 3: Use system defaults for parameters
        if !configurationSuccess {
            print("🔄 Trying Configuration 3: System defaults...")
            do {
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [])
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                configurationSuccess = true
                print("✅ Configuration 3 successful!")
            } catch {
                print("❌ Configuration 3 failed: \(error)")
            }
        }
        
        // Configuration 4: Minimal - just recording category
        if !configurationSuccess {
            print("🔄 Trying Configuration 4: Minimal recording...")
            do {
                try audioSession.setCategory(.record)
                try audioSession.setActive(true)
                configurationSuccess = true
                print("✅ Configuration 4 successful!")
            } catch {
                print("❌ Configuration 4 failed: \(error)")
            }
        }
        
        // Configuration 5: Last resort - playback category (won't record but won't crash)
        if !configurationSuccess {
            print("🔄 Trying Configuration 5: Last resort...")
            do {
                try audioSession.setCategory(.playback)
                try audioSession.setActive(true)
                configurationSuccess = true
                print("⚠️ Configuration 5 successful (playback only - recording may not work)")
            } catch {
                print("❌ All configurations failed!")
            }
        }
        
        guard configurationSuccess else {
            let error = NSError(domain: "AudioSessionConfig", code: -50, userInfo: [
                NSLocalizedDescriptionKey: "Failed to configure audio session with any fallback method. This device may not support audio recording."
            ])
            throw error
        }
        
        // Log final successful configuration
        print("📊 Final audio session configuration:")
        print("  - Category: \(audioSession.category)")
        print("  - Mode: \(audioSession.mode)")
        print("  - Sample rate: \(audioSession.sampleRate)")
        print("  - Input channels: \(audioSession.inputNumberOfChannels)")
        print("  - Input available: \(audioSession.isInputAvailable)")
        print("  - IO buffer duration: \(audioSession.ioBufferDuration)")
        
        // Special handling for simulator
        #if targetEnvironment(simulator)
        print("⚠️ Running in iOS Simulator")
        if !audioSession.isInputAvailable {
            print("⚠️ Simulator has limited audio input support")
            print("💡 For full functionality, test on a real iOS device")
        }
        #endif
        
        print("✅ Audio session configured successfully!")
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
        
        print("🎙️ Starting recording setup...")
        
        // Configure audio session first
        try configureAudioSession()
        
        recordingURL = url
        startTime = Date()
        
        // Ensure directory exists
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        // Stop and reset audio engine to ensure clean state
        if audioEngine.isRunning {
            audioEngine.stop()
            print("🛑 Stopped existing audio engine")
        }
        
        // Remove any existing taps
        inputNode.removeTap(onBus: 0)
        
        // Use the input node's native format to avoid format mismatch
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        print("🎧 Input format: Sample Rate=\(nativeFormat.sampleRate), Channels=\(nativeFormat.channelCount)")
        
        // Create recording format compatible with AAC encoding
        let recordingFormat = AVAudioFormat(standardFormatWithSampleRate: nativeFormat.sampleRate, channels: 1)!
        self.inputFormat = nativeFormat
        self.recordingFormat = recordingFormat
        
        // Create audio file with compatible settings
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: nativeFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        print("📝 Creating audio file with settings: \(settings)")
        audioFile = try AVAudioFile(forWriting: url, settings: settings)
        
        // Install tap using native input format
        let bufferSize: AVAudioFrameCount = 4096
        print("🎵 Installing audio tap with buffer size \(bufferSize) and format \(nativeFormat)")
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nativeFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // Write to audio file if recording
            if self.isRecordingActive, let audioFile = self.audioFile {
                // Convert to recording format if necessary
                if nativeFormat.sampleRate != recordingFormat.sampleRate || nativeFormat.channelCount != recordingFormat.channelCount {
                    // Create converter for different formats
                    if let converter = AVAudioConverter(from: nativeFormat, to: recordingFormat) {
                        let convertedBuffer = AVAudioPCMBuffer(pcmFormat: recordingFormat, frameCapacity: buffer.frameCapacity)!
                        var error: NSError?
                        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                            outStatus.pointee = .haveData
                            return buffer
                        }
                        
                        if status == .haveData && convertedBuffer.frameLength > 0 {
                            do {
                                try audioFile.write(from: convertedBuffer)
                            } catch {
                                print("❌ Recording write error (converted): \(error.localizedDescription)")
                            }
                        }
                    }
                } else {
                    // Formats match, write directly
                    do {
                        try audioFile.write(from: buffer)
                    } catch {
                        print("❌ Recording write error (direct): \(error.localizedDescription)")
                    }
                }
            }
            
            // Send to speech recognition if enabled
            if self.transcriptionEnabled {
                self.recognitionRequest?.append(buffer)
            }
            
            // Update power levels for UI
            self.updatePowerLevel(from: buffer)
        }
        
        // Start audio engine with detailed error handling
        print("▶️ Starting audio engine...")
        do {
            // Check if input is available
            if !audioSession.isInputAvailable {
                print("⚠️ No audio input available - this might be a simulator issue")
            }
            
            try audioEngine.start()
            print("✅ Audio engine started successfully")
            print("📊 Audio engine state: Running=\(audioEngine.isRunning)")
            
        } catch {
            print("❌ Audio engine start failed: \(error)")
            if let nsError = error as NSError? {
                print("❌ Engine error domain: \(nsError.domain), code: \(nsError.code)")
                print("❌ Engine error description: \(nsError.localizedDescription)")
                
                // Check for common error codes
                if nsError.code == -50 {
                    print("❌ Error -50: Parameter error - likely audio session or format issue")
                    print("📊 Debug info: Input available=\(audioSession.isInputAvailable), Category=\(audioSession.category)")
                }
            }
            throw error
        }
        
        isRecordingActive = true
        startMetering()
        
        print("🎙️ Recording started successfully to \(url.lastPathComponent)")
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
        guard let startTime = self.startTime else { 
            print("⚠️ No start time found, returning 0 duration")
            return 0
        }
        
        print("🛑 Stopping recording...")
        isRecordingActive = false
        stopMetering()
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Close audio file
        audioFile = nil
        
        // If transcription is also active, coordinate the shutdown
        if transcriptionEnabled {
            print("🔄 Recording and transcription both active, coordinating shutdown...")
            
            // Stop transcription gracefully first
            stopTranscription()
            
            // Then stop audio engine and cleanup
            inputNode.removeTap(onBus: 0)
            if audioEngine.isRunning {
                audioEngine.stop()
                print("🛑 Audio engine stopped")
            }
        } else {
            // Only recording was active, simple cleanup
            inputNode.removeTap(onBus: 0)
            if audioEngine.isRunning {
                audioEngine.stop()
                print("🛑 Audio engine stopped")
            }
        }
        
        // Reset recording state
        self.startTime = nil
        recordingURL = nil
        inputFormat = nil
        recordingFormat = nil
        
        print("✅ Recording stopped successfully, duration: \(String(format: "%.2f", duration))s")
        return duration
    }
    
    // MARK: - Transcription Functions
    
    func startTranscription() throws {
        guard !transcriptionEnabled else { return }
        
        // Configure audio session if needed
        try configureAudioSession()
        
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
        
        // Set up audio tap if not already recording
        if !isRecordingActive {
            // Stop and reset audio engine to ensure clean state
            if audioEngine.isRunning {
                audioEngine.stop()
            }
            
            // Remove any existing taps
            inputNode.removeTap(onBus: 0)
            
            // Use native input format for transcription
            let nativeFormat = inputNode.outputFormat(forBus: 0)
            print("🎙️ Transcription using native format: Sample Rate=\(nativeFormat.sampleRate), Channels=\(nativeFormat.channelCount)")
            
            // Install tap for transcription only
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, time in
                guard let self = self else { return }
                
                // Send to speech recognition
                if self.transcriptionEnabled {
                    self.recognitionRequest?.append(buffer)
                }
                
                // Update power levels for UI
                self.updatePowerLevel(from: buffer)
            }
            
            // Start audio engine
            try audioEngine.start()
            print("🎙️ AudioEngine started for transcription")
        }
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    let isFinal = result.isFinal
                    self?.onTranscriptUpdate?(text, isFinal)
                }
                
                if let error = error {
                    let nsError = error as NSError
                    
                    // Filter out expected errors during normal shutdown
                    if nsError.code == 301 && nsError.domain == "kLSRErrorDomain" {
                        // Code 301 = "Recognition request was canceled" - this is expected during cleanup
                        print("🔇 Speech recognition ended normally (request canceled during cleanup)")
                    } else if nsError.code == 216 {
                        // Code 216 = Speech recognition service unavailable
                        print("⚠️ Speech recognition service unavailable: \(error)")
                        self?.onError?(error)
                    } else {
                        print("❌ Unexpected speech recognition error: \(error)")
                        self?.onError?(error)
                        
                        // Auto-restart for recoverable errors (excluding cancellation)
                        if nsError.code != 301 && nsError.code != 216 {
                            print("🔄 Attempting to restart speech recognition...")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                if self?.transcriptionEnabled == true {
                                    try? self?.startTranscription()
                                }
                            }
                        }
                    }
                }
            }
        }
        
        transcriptionEnabled = true
        print("🗣️ AudioSessionManager: Transcription started")
    }
    
    func stopTranscription() {
        guard transcriptionEnabled else { 
            print("⚠️ Transcription already stopped, skipping...")
            return 
        }
        
        print("🔇 Stopping transcription gracefully...")
        transcriptionEnabled = false
        
        // Step 1: Gracefully end audio input
        if let recognitionRequest = recognitionRequest {
            print("📋 Ending audio input to speech recognizer...")
            recognitionRequest.endAudio()
        }
        
        // Step 2: Give recognition task time to finish processing
        if let recognitionTask = recognitionTask {
            print("⏳ Allowing recognition task to finish...")
            
            // Store reference to avoid race conditions
            let taskToFinish = recognitionTask
            
            // Only finish if it's still running after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if taskToFinish.state == .running {
                    print("🛑 Recognition task still running, finishing gracefully...")
                    taskToFinish.finish()
                } else {
                    print("✅ Recognition task completed naturally")
                }
                
                // Clean up references after everything is done
                DispatchQueue.main.async { [weak self] in
                    self?.recognitionRequest = nil
                    self?.recognitionTask = nil
                    self?.speechRecognizer = nil
                    print("🧹 Speech recognition resources cleaned up")
                }
            }
        } else {
            // No recognition task, clean up immediately
            recognitionRequest = nil
            speechRecognizer = nil
            print("🧹 Speech recognition resources cleaned up (no active task)")
        }
        
        // Step 3: Only stop audio engine and remove tap if recording is not active
        // AND if this wasn't called from stopRecording (which handles engine cleanup)
        if !isRecordingActive {
            print("🔊 Stopping audio engine (recording not active)...")
            do {
                inputNode.removeTap(onBus: 0)
                print("✅ Audio tap removed")
            } catch {
                print("⚠️ Error removing audio tap: \(error)")
            }
            
            if audioEngine.isRunning {
                audioEngine.stop()
                print("🛑 Audio engine stopped")
            }
        } else {
            print("🔊 Keeping audio engine running (recording still active)")
        }
        
        print("✅ Transcription stopped gracefully")
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
        print("🔄 Deactivating audio session...")
        
        // Stop all operations
        if isRecordingActive {
            _ = try? stopRecording()
        }
        
        stopTranscription()
        
        // Stop audio engine safely
        if audioEngine.isRunning {
            // Remove taps first to avoid crashes
            do {
                inputNode.removeTap(onBus: 0)
            } catch {
                print("⚠️ Error removing tap: \(error)")
            }
            audioEngine.stop()
            print("🛑 Audio engine stopped")
        }
        
        // Deactivate audio session
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            print("🔊 Audio session deactivated")
        } catch {
            print("⚠️ Error deactivating audio session: \(error)")
        }
        
        // Reset state
        recordingURL = nil
        audioFile = nil
        startTime = nil
        currentPower = -160
        inputFormat = nil
        recordingFormat = nil
        
        print("✅ AudioSessionManager: Session cleanup complete")
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
    
    var isTranscriptionActive: Bool {
        return transcriptionEnabled
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
