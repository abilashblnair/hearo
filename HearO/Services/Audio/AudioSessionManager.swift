import Foundation
import AVFoundation
import Speech
import UIKit
import CallKit

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
    
    // MARK: - Interruption State
    private var wasRecordingBeforeInterruption = false
    private var wasTranscribingBeforeInterruption = false
    private var interruptionCount = 0
    private var lastInterruptionTime: Date?
    private var resumeTimer: Timer?
    private var callObserver: CXCallObserver?
    private var isCallActive = false
    
    // MARK: - Interruption Control Settings
    private var shouldPauseOnInterruption = true
    private var shouldAutoResumeAfterInterruption = true
    private var maximumAutoResumeAttempts = 3
    private var currentResumeAttempts = 0
    
    // MARK: - Transcription State
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var transcriptionEnabled = false
    
    // MARK: - Transcript Cache
    private var cachedTranscriptLines: [String] = []
    private var cachedPartialText: String = ""
    private var isTranscriptCacheValid = false
    
    // MARK: - Callbacks
    var onTranscriptUpdate: ((String, Bool) -> Void)?
    var onPowerUpdate: ((Float) -> Void)?
    var onError: ((Error) -> Void)?
    var onInterruptionBegan: (() -> Void)?
    var onRecordingPaused: (() -> Void)?
    var onRecordingResumed: (() -> Void)?
    var onAutoResumeAttemptFailed: ((Int, Error) -> Void)?
    var onTranscriptCacheRestored: (([String], String) -> Void)?
    
    // MARK: - Native Speech Recognition
    private var isNativeTranscriptionEnabled = false
    
    private override init() {
        super.init()
        setupNotifications()
        setupCallObserver()
    }
    
    // MARK: - Session Management
    
    func requestPermissions() async throws {
        // Request microphone permission
        if #available(iOS 17.0, *) {
            try await withCheckedThrowingContinuation { cont in
                AVAudioApplication.requestRecordPermission { granted in
                    if granted { 
                        cont.resume() 
                    } else {
                        cont.resume(throwing: NSError(domain: "MicPermission", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied by user"]))
                    }
                }
            }
        } else {
            try await withCheckedThrowingContinuation { cont in
                audioSession.requestRecordPermission { granted in
                    if granted { 
                        cont.resume() 
                    } else {
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
        // If a call is active, don't try to configure audio session
        if isCallActive {
            throw NSError(domain: "AudioSessionConfig", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Cannot configure audio session while call is active"
            ])
        }
        
        // Progressive configuration approach - try from most to least restrictive
        var configurationSuccess = false
        var lastError: Error?
        
        // Configuration 1: Optimized for interruption handling
        if !configurationSuccess {
            do {
                try audioSession.setCategory(
                    .playAndRecord, 
                    mode: .default, 
                    options: [
                        .allowBluetooth,
                        .allowBluetoothA2DP,
                        .allowAirPlay,
                        .mixWithOthers,
                        .duckOthers,
                        .interruptSpokenAudioAndMixWithOthers
                    ]
                )
                try audioSession.setPreferredSampleRate(44100.0)
                try audioSession.setPreferredInputNumberOfChannels(1)
                try audioSession.setPreferredIOBufferDuration(0.02)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                configurationSuccess = true
            } catch {
                lastError = error
            }
        }
        
        // Configuration 2: Conservative with fewer options
        if !configurationSuccess {
            do {
                try audioSession.setCategory(
                    .playAndRecord, 
                    mode: .default, 
                    options: [.allowBluetooth, .mixWithOthers]
                )
                try audioSession.setPreferredSampleRate(44100.0)
                try audioSession.setPreferredInputNumberOfChannels(1)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                configurationSuccess = true
            } catch {
                lastError = error
            }
        }
        
        // Configuration 3: Basic with mix option only
        if !configurationSuccess {
            do {
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers])
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                configurationSuccess = true
            } catch {
                lastError = error
            }
        }
        
        // Configuration 4: No mixing (exclusive access)
        if !configurationSuccess {
            do {
                try audioSession.setCategory(.playAndRecord, mode: .default)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                configurationSuccess = true
            } catch {
                lastError = error
            }
        }
        
        // Configuration 5: Recording only
        if !configurationSuccess {
            do {
                try audioSession.setCategory(.record)
                try audioSession.setActive(true)
                configurationSuccess = true
            } catch {
                lastError = error
            }
        }
        
        guard configurationSuccess else {
            let error = NSError(domain: "AudioSessionConfig", code: -50, userInfo: [
                NSLocalizedDescriptionKey: "Failed to configure audio session with any fallback method. Last error: \(lastError?.localizedDescription ?? "Unknown")"
            ])
            throw error
        }
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
        
    }
    
    func startRecording(to url: URL) throws {
        guard !isRecordingActive else { throw NSError(domain: "AudioSession", code: 1, userInfo: [NSLocalizedDescriptionKey: "Recording already active"]) }
        
        // Configure audio session first
        try configureAudioSession()
        
        recordingURL = url
        startTime = Date()
        
        // Ensure directory exists
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        // Stop and reset audio engine to ensure clean state
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        // Remove any existing taps
        inputNode.removeTap(onBus: 0)
        
        // Use the input node's native format to avoid format mismatch
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        
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
        
        audioFile = try AVAudioFile(forWriting: url, settings: settings)
        
        // Install tap using native input format
        let bufferSize: AVAudioFrameCount = 4096
        
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
                                // Silently handle write errors to avoid spam
                            }
                        }
                    }
                } else {
                    // Formats match, write directly
                    do {
                        try audioFile.write(from: buffer)
                    } catch {
                        // Silently handle write errors to avoid spam
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
        
        // Start audio engine
        do {
            try audioEngine.start()
        } catch {
            throw error
        }
        
        isRecordingActive = true
        startMetering()
    }
    
    func pauseRecording() throws {
        guard isRecordingActive else { 
            return 
        }
        
        // Pause recording but keep audio file and engine state intact for resume
        isRecordingActive = false
        stopMetering()
    }
    
    func resumeRecording() throws {
        guard !isRecordingActive, let recordingURL = recordingURL else { 
            throw NSError(domain: "AudioSession", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot resume: No active recording session"])
        }
        
        // Configure audio session first
        try configureAudioSession()
        
        // Check if audio engine is running, restart if needed
        if !audioEngine.isRunning {
            // Remove any existing taps to avoid conflicts
            inputNode.removeTap(onBus: 0)
            
            // Use the saved formats or detect them again
            let nativeFormat = inputNode.outputFormat(forBus: 0)
            let recordingFormat = self.recordingFormat ?? AVAudioFormat(standardFormatWithSampleRate: nativeFormat.sampleRate, channels: 1)!
            
            self.inputFormat = nativeFormat
            self.recordingFormat = recordingFormat
            
            // Ensure we have a valid audio file (should still be open from initial recording)
            if audioFile == nil {
                audioFile = try AVAudioFile(forWriting: recordingURL, settings: recordingFormat.settings)
            }
            
            guard audioFile != nil else {
                throw NSError(domain: "AudioSession", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to access audio file for resume"])
            }
            
            // Install tap to continue recording (with transcription support)
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, time in
                guard let self = self else { return }
                
                // Write to audio file if recording is active
                if self.isRecordingActive, let audioFile = self.audioFile {
                    // Convert and write to file using the same logic as startRecording
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
                                    DispatchQueue.main.async {
                                        self.onError?(error)
                                    }
                                }
                            }
                        }
                    } else {
                        // Formats match, write directly
                        do {
                            try audioFile.write(from: buffer)
                        } catch {
                            DispatchQueue.main.async {
                                self.onError?(error)
                            }
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
            
            // Start audio engine
            try audioEngine.start()
        } else {
            
            // Ensure we still have a valid audio file
            if audioFile == nil {
                let recordingFormat = self.recordingFormat ?? AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
                audioFile = try AVAudioFile(forWriting: recordingURL, settings: recordingFormat.settings)
            }
            
            // The tap should still be installed, but let's verify the audio file is still good
            guard audioFile != nil else {
                throw NSError(domain: "AudioSession", code: 4, userInfo: [NSLocalizedDescriptionKey: "Audio file is invalid for resume"])
            }
            
        }
        
        // Resume recording state
        isRecordingActive = true
        startMetering()
        
        
        // Verify audio input is available
        if !audioSession.isInputAvailable {
        }
    }
    
    func stopRecording() throws -> TimeInterval {
        guard let startTime = self.startTime else { 
            return 0
        }
        
        isRecordingActive = false
        stopMetering()
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Close audio file
        audioFile = nil
        
        // If transcription is also active, coordinate the shutdown
        if transcriptionEnabled {
            
            // Stop transcription gracefully first
            stopTranscription()
            
            // Then stop audio engine and cleanup
            inputNode.removeTap(onBus: 0)
            if audioEngine.isRunning {
                audioEngine.stop()
            }
        } else {
            // Only recording was active, simple cleanup
            inputNode.removeTap(onBus: 0)
            if audioEngine.isRunning {
                audioEngine.stop()
            }
        }
        
        // Reset recording state
        self.startTime = nil
        recordingURL = nil
        inputFormat = nil
        recordingFormat = nil
        

        return duration
    }
    
    // MARK: - Transcription Functions
    
    func startTranscription() throws {
        guard !transcriptionEnabled else { return }
        
        // Configure audio session if needed
        try configureAudioSession()
        
        // CRITICAL: Check speech authorization status before starting
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if authStatus != .authorized {
            throw NSError(domain: "SpeechRecognition", code: 0, userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission denied: \(authStatus). Please check app permissions in Settings."])
        }
        
        // Initialize speech recognizer
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        
        if let speechRecognizer = speechRecognizer {
            if !speechRecognizer.isAvailable {
                
                // Wait a moment and try again - sometimes the recognizer needs time after interruption
                Thread.sleep(forTimeInterval: 0.5)
                
                if !speechRecognizer.isAvailable {
                    throw NSError(domain: "SpeechRecognition", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer not available after interruption - may need system restart"])
                }
            }
        } else {
            throw NSError(domain: "SpeechRecognition", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create speech recognizer"])
        }
        
        guard let speechRecognizer = speechRecognizer else {
            throw NSError(domain: "SpeechRecognition", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is nil"])
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
        } else {
            // Recording is already active - need to reinstall tap to include transcription
            
            // Verify audio engine is running (should be from recording)
            if !audioEngine.isRunning {
                throw NSError(domain: "AudioSession", code: 4, userInfo: [NSLocalizedDescriptionKey: "Audio engine not running for existing recording"])
            }
            
            // CRITICAL FIX: Reinstall the audio tap to include transcription support
            
            // Remove existing tap
            inputNode.removeTap(onBus: 0)
            
            // Get current audio formats
            let nativeFormat = inputNode.outputFormat(forBus: 0)
            let recordingFormat = self.recordingFormat ?? AVAudioFormat(standardFormatWithSampleRate: nativeFormat.sampleRate, channels: 1)!
            
            
            // Reinstall tap with BOTH recording AND transcription support
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, time in
                guard let self = self else { return }
                
                // Write to audio file if recording is active
                if self.isRecordingActive, let audioFile = self.audioFile {
                    // Convert and write to file using the same logic as resumeRecording
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
                                    DispatchQueue.main.async {
                                        self.onError?(error)
                                    }
                                }
                            }
                        }
                    } else {
                        // Formats match, write directly
                        do {
                            try audioFile.write(from: buffer)
                        } catch {
                            DispatchQueue.main.async {
                                self.onError?(error)
                            }
                        }
                    }
                }
                
                // Send to speech recognition when enabled
                if self.transcriptionEnabled {
                    self.recognitionRequest?.append(buffer)
                }
                
                // Update power levels for UI
                self.updatePowerLevel(from: buffer)
            }
            
        }
        
        // Start recognition task
        
        
        // Create the recognition task
        // CRITICAL: Track if we're getting any callbacks at all
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
                        // Expected during cleanup - ignore
                    } else if nsError.code == 216 {
                        // Speech recognition service unavailable
                        self?.onError?(error)
                    } else {
                        self?.onError?(error)
                        
                        // Auto-restart for recoverable errors (excluding cancellation)
                        if nsError.code != 301 && nsError.code != 216 {
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
        
        // Verify recognition task was created successfully
        if recognitionTask == nil {
            throw NSError(domain: "SpeechRecognition", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create speech recognition task"])
        }
        
        transcriptionEnabled = true
    }
    
    func stopTranscription() {
        guard transcriptionEnabled else { 
            return 
        }
        
        transcriptionEnabled = false
        
        // Step 1: Gracefully end audio input
        if let recognitionRequest = recognitionRequest {
            // End audio input to speech recognizer
            recognitionRequest.endAudio()
        }
        
        // Step 2: Give recognition task time to finish processing
        if let recognitionTask = recognitionTask {
            // Allow recognition task to finish
            
            // Store reference to avoid race conditions
            let taskToFinish = recognitionTask
            
            // Only finish if it's still running after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if taskToFinish.state == .running {
                    // Recognition task still running, finish gracefully
                    taskToFinish.finish()
                }
                
                // Clean up references after everything is done
                DispatchQueue.main.async { [weak self] in
                    self?.recognitionRequest = nil
                    self?.recognitionTask = nil
                    self?.speechRecognizer = nil
                }
            }
        } else {
            // No recognition task, clean up immediately
            recognitionRequest = nil
            speechRecognizer = nil
        }
        
        // Step 3: Only stop audio engine and remove tap if recording is not active
        // AND if this wasn't called from stopRecording (which handles engine cleanup)
        if !isRecordingActive {
            inputNode.removeTap(onBus: 0)
            if audioEngine.isRunning {
                audioEngine.stop()
            }
        }
        

    }
    
    /// Force restart speech recognition - useful when it gets stuck
    func forceRestartSpeechRecognition() {
        // Force restart speech recognition
        
        let wasEnabled = transcriptionEnabled
        
        if wasEnabled {
            // Stop current speech recognition
            
            // Force stop everything immediately (not graceful)
            transcriptionEnabled = false
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
            speechRecognizer = nil
            
            // Wait for cleanup
            
            // Wait a moment for cleanup
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                
                // Restart speech recognition after cleanup
                do {
                    try self.startTranscription()

                } catch {

                    self.onError?(error)
                }
            }
        } else {
            // Transcription wasn't enabled, start fresh
            do {
                try startTranscription()

            } catch {

                onError?(error)
            }
        }
    }
    
    // MARK: - Transcript Cache Management
    
    /// Cache current transcript state before interruption
    private func cacheTranscriptState(_ finalLines: [String], _ partialText: String) {
        cachedTranscriptLines = finalLines
        cachedPartialText = partialText
        isTranscriptCacheValid = true
    }
    
    /// Restore transcript cache after interruption
    private func restoreTranscriptCache() -> (lines: [String], partial: String)? {
        guard isTranscriptCacheValid else { return nil }
        return (cachedTranscriptLines, cachedPartialText)
    }
    
    /// Clear transcript cache
    private func clearTranscriptCache() {
        cachedTranscriptLines.removeAll()
        cachedPartialText = ""
        isTranscriptCacheValid = false
    }
    
    /// Public method to get cached transcript
    func getCachedTranscript() -> (lines: [String], partial: String) {
        return (cachedTranscriptLines, cachedPartialText)
    }
    
    /// Public method to manually cache transcript from UI
    func cacheTranscript(lines: [String], partial: String) {
        cacheTranscriptState(lines, partial)
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
            _ = try? stopRecording()
        }
        
        stopTranscription()
        
        // Stop audio engine safely
        if audioEngine.isRunning {
            // Remove taps first to avoid crashes
            inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        
        // Deactivate audio session
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Handle deactivation error silently
        }
        
        // Reset state
        recordingURL = nil
        audioFile = nil
        startTime = nil
        currentPower = -160
        inputFormat = nil
        recordingFormat = nil
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
    
    var wasRecordingActiveBeforeInterruption: Bool {
        return wasRecordingBeforeInterruption
    }
    
    var wasTranscriptionActiveBeforeInterruption: Bool {
        return wasTranscribingBeforeInterruption
    }
    
    // MARK: - Manual Resume Support
    
    /// Manually attempt to resume audio operations after an interruption
    /// This can be called by UI components if automatic resume fails
    func manualResumeAfterInterruption() {
        
        guard wasRecordingBeforeInterruption || wasTranscribingBeforeInterruption else {
            return
        }
        
        if isCallActive {
            scheduleResumeAttempt()
            return
        }
        
        attemptResume()
    }
    
    /// Check if there are pending operations waiting to resume
    var hasPendingResumeOperations: Bool {
        return wasRecordingBeforeInterruption || wasTranscribingBeforeInterruption
    }
    
    // MARK: - Interruption Configuration
    
    /// Configure interruption handling behavior
    /// - Parameters:
    ///   - pauseOnInterruption: Whether to automatically pause recording when interruptions occur
    ///   - autoResumeAfterInterruption: Whether to automatically resume after interruption ends
    ///   - maxAutoResumeAttempts: Maximum number of automatic resume attempts (1-10)
    func configureInterruptionHandling(
        pauseOnInterruption: Bool = true,
        autoResumeAfterInterruption: Bool = true,
        maxAutoResumeAttempts: Int = 3
    ) {
        self.shouldPauseOnInterruption = pauseOnInterruption
        self.shouldAutoResumeAfterInterruption = autoResumeAfterInterruption
        self.maximumAutoResumeAttempts = min(max(maxAutoResumeAttempts, 1), 10)
        
    }
    
    /// Permanently disable automatic resume for the current interruption
    func disableAutoResumeForCurrentInterruption() {
        guard wasRecordingBeforeInterruption || wasTranscribingBeforeInterruption else {
            return
        }
        
        resumeTimer?.invalidate()
        resumeTimer = nil
        currentResumeAttempts = maximumAutoResumeAttempts + 1 // Exceed limit
        
    }
    
    /// Manually force resume even if auto-resume was disabled
    func forceResumeAfterInterruption() {
        guard wasRecordingBeforeInterruption || wasTranscribingBeforeInterruption else {
            return
        }
        
        currentResumeAttempts = 0 // Reset attempt counter
        attemptResume()
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
        
        // Background/Foreground notifications for continuous recording
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    private func setupCallObserver() {
        callObserver = CXCallObserver()
        callObserver?.setDelegate(self, queue: DispatchQueue.main)
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        let _ = userInfo[AVAudioSessionInterruptionReasonKey] as? UInt
        let _ = userInfo[AVAudioSessionInterruptionWasSuspendedKey] as? Bool ?? false
        
        
        switch type {
        case .began:
            handleInterruptionBegan()
        case .ended:
            handleInterruptionEnded(userInfo: userInfo)
        @unknown default:
            break
        }
    }
    
    private func handleInterruptionBegan() {
        // Cancel any pending resume timer
        resumeTimer?.invalidate()
        resumeTimer = nil
        
        // Reset resume attempt counter
        currentResumeAttempts = 0
        
        // Save current state
        wasRecordingBeforeInterruption = isRecordingActive
        wasTranscribingBeforeInterruption = transcriptionEnabled
        lastInterruptionTime = Date()
        interruptionCount += 1
        
        // Notify UI about interruption to cache transcript before we stop it
        DispatchQueue.main.async { [weak self] in
            self?.onInterruptionBegan?()
        }
        
        // Pause recording if configured to do so
        if isRecordingActive && shouldPauseOnInterruption {
            do {
                try pauseRecording()
                
                // Notify UI about pause
                DispatchQueue.main.async { [weak self] in
                    self?.onRecordingPaused?()
                }
            } catch {
                onError?(error)
            }
        } else if isRecordingActive {
        }
        
        // Stop transcription but preserve audio engine for recording resume
        if transcriptionEnabled {
            // Only stop the recognition task, not the entire audio engine if recording is active
            if wasRecordingBeforeInterruption {
                // Stop only transcription components, keep audio engine running for recording
                recognitionTask?.cancel()
                recognitionTask = nil
                recognitionRequest = nil
                transcriptionEnabled = false
            } else {
                // No recording, safe to stop everything
                stopTranscription()
            }
        }
        
        // Update AudioStateManager to reflect interruption
        AudioStateManager.shared.stopRecording()
        AudioStateManager.shared.stopStandaloneTranscript()
        
    }
    
    private func handleInterruptionEnded(userInfo: [AnyHashable: Any]) {
        
        let options = AVAudioSession.InterruptionOptions(
            rawValue: userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        )
        
        
        // Check if auto-resume is disabled
        if !shouldAutoResumeAfterInterruption {
            return
        }
        
        // Check if we've exceeded maximum retry attempts
        if currentResumeAttempts >= maximumAutoResumeAttempts {
            return
        }
        
        // Don't resume immediately if a call is still active
        if isCallActive {
            scheduleResumeAttempt()
            return
        }
        
        // Attempt immediate resume if conditions are right
        if shouldAttemptResume(options: options) {
            attemptResume()
        } else {
            scheduleResumeAttempt()
        }
    }
    
    private func shouldAttemptResume(options: AVAudioSession.InterruptionOptions) -> Bool {
        // Always attempt resume if we were doing something before interruption
        if wasRecordingBeforeInterruption || wasTranscribingBeforeInterruption {
            return true
        }
        
        // Traditional check for .shouldResume option
        return options.contains(.shouldResume)
    }
    
    private func scheduleResumeAttempt(delaySeconds: Double = 2.0) {
        // Cancel any existing timer
        resumeTimer?.invalidate()
        
        // Schedule resume attempt with specified delay
        resumeTimer = Timer.scheduledTimer(withTimeInterval: delaySeconds, repeats: false) { [weak self] _ in
            self?.attemptResumeAfterDelay()
        }
        
    }
    
    private func attemptResumeAfterDelay() {
        
        if isCallActive {
            scheduleResumeAttempt()
            return
        }
        
        attemptResume()
    }
    
    private func attemptResume() {
        currentResumeAttempts += 1
        
        var resumeSuccessful = true
        var resumeError: Error?
        
        // First, try to reactivate audio session
        do {
            
            // Check if audio session is already active
            if audioSession.isOtherAudioPlaying {
            }
            
            try configureAudioSession()
            
            // Verify critical audio session properties
            
            if !audioSession.isInputAvailable {
                #if !targetEnvironment(simulator)
                #endif
            }
            
        } catch {
            resumeSuccessful = false
            resumeError = error
            onError?(error)
        }
        
        // Resume recording if it was active and session was reactivated
        if resumeSuccessful && wasRecordingBeforeInterruption {
            do {
                
                // CRITICAL: Verify audio engine state before resume
                if !audioEngine.isRunning {
                } else {
                }
                
                try resumeRecording()
                _ = AudioStateManager.shared.startRecording()
                
                // Verify audio is actually flowing
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    if let self = self {
                        if self.isRecordingActive && self.currentPower > -160 {
                        } else if self.isRecordingActive {
                        } else {
                        }
                    }
                }
                
            } catch {
                resumeSuccessful = false
                resumeError = error
                onError?(error)
            }
        }
        
        // Resume transcription if it was active and session was reactivated
        if resumeSuccessful && wasTranscribingBeforeInterruption {
            do {
                try startTranscription()
                
                // Restore cached transcript after a brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    if let self = self, let cachedData = self.restoreTranscriptCache() {
                        self.onTranscriptCacheRestored?(cachedData.lines, cachedData.partial)
                    }
                }
            } catch {
                resumeSuccessful = false
                resumeError = error
                onError?(error)
            }
        }
        
        if resumeSuccessful {
            // Reset interruption state on successful resume
            wasRecordingBeforeInterruption = false
            wasTranscribingBeforeInterruption = false
            currentResumeAttempts = 0
            
            // Notify UI about successful resume (for any type of operation)
            DispatchQueue.main.async { [weak self] in
                self?.onRecordingResumed?()
            }
            
        } else {
            // Handle failed resume attempt
            if currentResumeAttempts < maximumAutoResumeAttempts {
                scheduleResumeAttempt(delaySeconds: 3.0)
            } else {
                
                // Notify UI about failed auto-resume
                if let error = resumeError {
                    DispatchQueue.main.async { [weak self] in
                        self?.onAutoResumeAttemptFailed?(self?.currentResumeAttempts ?? 0, error)
                    }
                }
            }
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
    
    // MARK: - Background/Foreground Handlers
    
    @objc private func handleAppWillResignActive() {
        // Keep audio session active for background recording
        if isRecordingActive || transcriptionEnabled {
            try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        }
    }
    
    @objc private func handleAppDidBecomeActive() {
        // Ensure audio session is still active
        if isRecordingActive || transcriptionEnabled {
            try? configureAudioSession()
        }
    }
    
    @objc private func handleAppDidEnterBackground() {
        if isRecordingActive {
        }
        if transcriptionEnabled {
        }
        
        // Ensure audio session stays active for background recording
        if isRecordingActive || transcriptionEnabled {
            do {
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                onError?(error)
            }
        }
    }
    
    @objc private func handleAppWillEnterForeground() {
        // Refresh audio session configuration
        if isRecordingActive || transcriptionEnabled {
            do {
                try configureAudioSession()
            } catch {
                onError?(error)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        resumeTimer?.invalidate()
        callObserver?.setDelegate(nil, queue: nil)
        deactivateSession()
    }
}

// MARK: - CXCallObserverDelegate

extension AudioSessionManager: CXCallObserverDelegate {
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        let wasCallActive = isCallActive
        isCallActive = !call.hasEnded
        
        
        // If call just ended and we have pending resume operations
        if wasCallActive && !isCallActive {
            
            if wasRecordingBeforeInterruption || wasTranscribingBeforeInterruption {
                // Give a moment for the audio session to stabilize after call ends
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.attemptResume()
                }
            }
        }
        
        // If call just started while recording/transcribing (edge case)
        if !wasCallActive && isCallActive {
            if isRecordingActive || transcriptionEnabled {
                handleInterruptionBegan()
            }
        }
    }
}
