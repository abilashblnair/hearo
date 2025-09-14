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
    private var pauseStartTime: Date?
    private var totalPausedDuration: TimeInterval = 0
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
        
        print("🎙️ AudioSessionManager: Recording with native transcription started")
    }
    
    func startRecording(to url: URL) throws {
        guard !isRecordingActive else { throw NSError(domain: "AudioSession", code: 1, userInfo: [NSLocalizedDescriptionKey: "Recording already active"]) }
        
        // Configure audio session first
        try configureAudioSession()
        
        recordingURL = url
        startTime = Date()
        
        // Reset pause tracking for new recording
        totalPausedDuration = 0
        pauseStartTime = nil
        
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
        
        // Record when pause started for time tracking
        pauseStartTime = Date()
        
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
            print("✅ Audio engine restarted for recording resume")
        } else {
            print("✅ Audio engine still running from interruption")
            
            // Ensure we still have a valid audio file
            if audioFile == nil {
                print("⚠️ Audio file was lost, this shouldn't happen with engine still running")
                let recordingFormat = self.recordingFormat ?? AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
                audioFile = try AVAudioFile(forWriting: recordingURL, settings: recordingFormat.settings)
            }
            
            // The tap should still be installed, but let's verify the audio file is still good
            guard audioFile != nil else {
                throw NSError(domain: "AudioSession", code: 4, userInfo: [NSLocalizedDescriptionKey: "Audio file is invalid for resume"])
            }
            
            print("✅ Existing tap and audio file verified for resume")
        }
        
        // Calculate and accumulate paused time
        if let pauseStart = pauseStartTime {
            totalPausedDuration += Date().timeIntervalSince(pauseStart)
            pauseStartTime = nil
        }
        
        // Resume recording state
        isRecordingActive = true
        startMetering()
        
        print("▶️ Recording successfully resumed to \(recordingURL.lastPathComponent)")
        print("   📊 Final resume state: recording=\(isRecordingActive), engine=\(audioEngine.isRunning), file=\(audioFile != nil)")
        print("   📊 Audio session: active=\(audioSession.isOtherAudioPlaying), category=\(audioSession.category)")
        
        // Verify audio input is available
        if !audioSession.isInputAvailable {
            print("⚠️ WARNING: Audio input not available after resume!")
        } else {
            print("✅ Audio input is available")
        }
    }
    
    func stopRecording() throws -> TimeInterval {
        guard let startTime = self.startTime else { 
            print("⚠️ No start time found, returning 0 duration")
            return 0
        }
        
        print("🛑 Stopping recording...")
        isRecordingActive = false
        stopMetering()
        
        // Calculate final duration excluding paused time
        let totalElapsed = Date().timeIntervalSince(startTime)
        var duration = totalElapsed - totalPausedDuration
        
        // If we were paused when stopped, subtract the current pause duration
        if let pauseStart = pauseStartTime {
            duration -= Date().timeIntervalSince(pauseStart)
        }
        
        duration = max(0, duration)
        
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
        
        // Reset pause tracking
        totalPausedDuration = 0
        pauseStartTime = nil
        

        return duration
    }
    
    // MARK: - Transcription Functions
    
    func startTranscription() throws {
        print("🎤 === AudioSessionManager.startTranscription() called ===")
        print("   - transcriptionEnabled: \(transcriptionEnabled)")
        print("   - audioEngine.isRunning: \(audioEngine.isRunning)")
        print("   - isRecordingActive: \(isRecordingActive)")
        
        guard !transcriptionEnabled else { 
            print("🎤 Transcription already enabled, returning early")
            return 
        }
        
        // Configure audio session if needed
        try configureAudioSession()
        
        // CRITICAL: Check speech authorization status before starting
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        print("🎤 Speech authorization status: \(authStatus)")
        
        if authStatus != .authorized {
            print("❌ Speech recognition not authorized: \(authStatus)")
            print("   - This might be the reason why speech recognition isn't working after resume")
            throw NSError(domain: "SpeechRecognition", code: 0, userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission denied: \(authStatus). Please check app permissions in Settings."])
        }
        
        // Initialize speech recognizer
        print("🗣️ Initializing speech recognizer...")
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        
        if let speechRecognizer = speechRecognizer {
            print("   - Speech recognizer created successfully")
            print("   - Speech recognizer available: \(speechRecognizer.isAvailable)")
            if !speechRecognizer.isAvailable {
                print("   ❌ Speech recognizer is not available!")
                print("   - This might be due to system restrictions after interruption")
                print("   - Waiting a moment and trying again...")
                
                // Wait a moment and try again - sometimes the recognizer needs time after interruption
                Thread.sleep(forTimeInterval: 0.5)
                print("   - Rechecking availability: \(speechRecognizer.isAvailable)")
                
                if !speechRecognizer.isAvailable {
                    throw NSError(domain: "SpeechRecognition", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer not available after interruption - may need system restart"])
                }
            }
        } else {
            print("   ❌ Failed to create speech recognizer!")
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
            print("🎙️ Transcription joining existing recording session")
            print("   - Audio engine running: \(audioEngine.isRunning)")
            print("   - Recording active: \(isRecordingActive)")
            
            // Verify audio engine is running (should be from recording)
            if !audioEngine.isRunning {
                print("⚠️ Audio engine not running despite recording being active - this is a problem!")
                throw NSError(domain: "AudioSession", code: 4, userInfo: [NSLocalizedDescriptionKey: "Audio engine not running for existing recording"])
            }
            
            // CRITICAL FIX: Reinstall the audio tap to include transcription support
            print("🔄 Reinstalling audio tap to add transcription support to existing recording")
            
            // Remove existing tap
            inputNode.removeTap(onBus: 0)
            
            // Get current audio formats
            let nativeFormat = inputNode.outputFormat(forBus: 0)
            let recordingFormat = self.recordingFormat ?? AVAudioFormat(standardFormatWithSampleRate: nativeFormat.sampleRate, channels: 1)!
            
            print("   - Using formats: native=\(nativeFormat.sampleRate)Hz/\(nativeFormat.channelCount)ch, recording=\(recordingFormat.sampleRate)Hz/\(recordingFormat.channelCount)ch")
            
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
                                    print("❌ Error writing to recording file during transcription join: \(error)")
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
                            print("❌ Error writing to recording file during transcription join: \(error)")
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
            
            print("✅ Audio tap reinstalled with both recording and transcription support")
        }
        
        // Start recognition task
        print("🗣️ Starting speech recognition task...")
        print("   - Speech recognizer available: \(speechRecognizer.isAvailable)")
        print("   - Audio session active: \(!audioSession.isOtherAudioPlaying)")
        
        print("🗣️ Creating speech recognition task...")
        
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
        print("✅ AudioSessionManager.startTranscription() completed successfully")
        print("   - transcriptionEnabled: \(transcriptionEnabled)")
        print("   - recognitionTask created: \(recognitionTask != nil)")
        print("   - recognitionRequest created: \(recognitionRequest != nil)")
        print("   - speechRecognizer available: \(speechRecognizer.isAvailable)")
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
    
    /// Enable transcription during active recording - bypasses the guard for mid-recording starts
    func enableTranscriptionDuringRecording() throws {
        guard isRecordingActive else {
            throw NSError(domain: "AudioSession", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cannot enable transcription during recording: No active recording session"])
        }
        
        print("🎤 Enabling transcription during active recording session")
        
        // Temporarily reset the flag to bypass the guard in startTranscription
        let wasTranscriptionEnabled = transcriptionEnabled
        transcriptionEnabled = false
        
        // Now call startTranscription which will handle the mid-recording case properly
        do {
            try startTranscription()
            print("✅ Transcription successfully enabled during recording")
        } catch {
            // Restore the previous state if starting failed
            transcriptionEnabled = wasTranscriptionEnabled
            print("❌ Failed to enable transcription during recording: \(error)")
            throw error
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
        
        // Reset pause tracking
        totalPausedDuration = 0
        pauseStartTime = nil
    }
    
    // MARK: - Public Properties
    
    var isRecording: Bool { isRecordingActive }
    var currentRecordingURL: URL? { recordingURL }
    var isSessionActive: Bool { 
        // Session is active if:
        // 1. Currently recording, OR
        // 2. Audio engine is running for transcription, OR  
        // 3. There's a paused recording that can be resumed (recordingURL exists)
        return isRecordingActive || audioEngine.isRunning || recordingURL != nil
    }
    var averagePower: Float { currentPower }
    
    var currentTime: TimeInterval {
        guard let startTime = startTime else { return 0 }
        
        let totalElapsed = Date().timeIntervalSince(startTime)
        var adjustedElapsed = totalElapsed - totalPausedDuration
        
        // If currently paused, add the current pause duration
        if !isRecordingActive, let pauseStart = pauseStartTime {
            adjustedElapsed -= Date().timeIntervalSince(pauseStart)
        }
        
        return max(0, adjustedElapsed)
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
        print("🔄 Manual resume requested by UI")
        
        guard wasRecordingBeforeInterruption || wasTranscribingBeforeInterruption else {
            print("   - No operations were active before interruption")
            return
        }
        
        if isCallActive {
            print("   - Call still active, cannot resume yet")
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
        
        print("🔧 Interruption handling configured:")
        print("   - Pause on interruption: \(pauseOnInterruption)")
        print("   - Auto resume: \(autoResumeAfterInterruption)")  
        print("   - Max resume attempts: \(self.maximumAutoResumeAttempts)")
    }
    
    /// Permanently disable automatic resume for the current interruption
    func disableAutoResumeForCurrentInterruption() {
        guard wasRecordingBeforeInterruption || wasTranscribingBeforeInterruption else {
            print("⚠️ No active interruption to disable auto-resume for")
            return
        }
        
        resumeTimer?.invalidate()
        resumeTimer = nil
        currentResumeAttempts = maximumAutoResumeAttempts + 1 // Exceed limit
        
        print("🔕 Auto-resume disabled for current interruption")
    }
    
    /// Manually force resume even if auto-resume was disabled
    func forceResumeAfterInterruption() {
        guard wasRecordingBeforeInterruption || wasTranscribingBeforeInterruption else {
            print("⚠️ No operations were active before interruption")
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
        
        let interruptionReason = userInfo[AVAudioSessionInterruptionReasonKey] as? UInt
        let wasSuspended = userInfo[AVAudioSessionInterruptionWasSuspendedKey] as? Bool ?? false
        
        print("🔔 Audio interruption: \(type == .began ? "BEGAN" : "ENDED")")
        print("   - Reason: \(interruptionReason?.description ?? "unknown")")
        print("   - Was suspended: \(wasSuspended)")
        print("   - Call active: \(isCallActive)")
        print("   - Currently recording: \(isRecordingActive)")
        print("   - Currently transcribing: \(transcriptionEnabled)")
        
        switch type {
        case .began:
            handleInterruptionBegan()
        case .ended:
            handleInterruptionEnded(userInfo: userInfo)
        @unknown default:
            print("⚠️ Unknown interruption type")
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
                print("   - ✅ Recording paused successfully")
                
                // Notify UI about pause
                DispatchQueue.main.async { [weak self] in
                    self?.onRecordingPaused?()
                }
            } catch {
                print("   - ❌ Failed to pause recording: \(error)")
                onError?(error)
            }
        } else if isRecordingActive {
            print("   - ⚠️ Recording NOT paused (pauseOnInterruption disabled)")
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
                print("   - ✅ Transcription stopped (audio engine preserved for recording)")
            } else {
                // No recording, safe to stop everything
                stopTranscription()
                print("   - ✅ Transcription stopped")
            }
        }
        
        // Update AudioStateManager to reflect interruption
        AudioStateManager.shared.stopRecording()
        AudioStateManager.shared.stopStandaloneTranscript()
        
        print("🔴 Interruption handling complete")
    }
    
    private func handleInterruptionEnded(userInfo: [AnyHashable: Any]) {
        print("🟢 Interruption ended, evaluating resume conditions...")
        
        let options = AVAudioSession.InterruptionOptions(
            rawValue: userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        )
        
        print("   - Interruption options: \(options)")
        print("   - Should resume suggested: \(options.contains(.shouldResume))")
        print("   - Call still active: \(isCallActive)")
        print("   - Time since interruption: \(lastInterruptionTime?.timeIntervalSinceNow ?? 0)s")
        print("   - Auto-resume enabled: \(shouldAutoResumeAfterInterruption)")
        print("   - Resume attempts: \(currentResumeAttempts)/\(maximumAutoResumeAttempts)")
        
        // Check if auto-resume is disabled
        if !shouldAutoResumeAfterInterruption {
            print("   - 🔕 Auto-resume disabled - manual intervention required")
            return
        }
        
        // Check if we've exceeded maximum retry attempts
        if currentResumeAttempts >= maximumAutoResumeAttempts {
            print("   - 🛑 Maximum auto-resume attempts reached - manual intervention required")
            return
        }
        
        // Don't resume immediately if a call is still active
        if isCallActive {
            print("   - ⏳ Call still active, will retry resume later")
            scheduleResumeAttempt()
            return
        }
        
        // Attempt immediate resume if conditions are right
        if shouldAttemptResume(options: options) {
            attemptResume()
        } else {
            print("   - ⏳ Conditions not met for immediate resume, scheduling retry")
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
        
        print("   - ⏰ Scheduled resume attempt in \(delaySeconds) seconds")
    }
    
    private func attemptResumeAfterDelay() {
        print("🔄 Attempting delayed resume...")
        print("   - Call still active: \(isCallActive)")
        print("   - Audio session interrupted: \(audioSession.isOtherAudioPlaying)")
        
        if isCallActive {
            print("   - ⏳ Call still active, will retry again")
            scheduleResumeAttempt()
            return
        }
        
        attemptResume()
    }
    
    private func attemptResume() {
        currentResumeAttempts += 1
        print("🟢 Attempting to resume audio operations (attempt \(currentResumeAttempts)/\(maximumAutoResumeAttempts))...")
        print("   - State before resume: recording=\(wasRecordingBeforeInterruption), transcription=\(wasTranscribingBeforeInterruption)")
        print("   - Current audio state: recording=\(isRecordingActive), transcription=\(transcriptionEnabled)")
        print("   - Audio session active: \(audioSession.isOtherAudioPlaying)")
        
        var resumeSuccessful = true
        var resumeError: Error?
        
        // First, try to reactivate audio session
        do {
            print("   - 🔄 Attempting to reactivate audio session...")
            
            // Check if audio session is already active
            if audioSession.isOtherAudioPlaying {
                print("   - ⚠️ Other audio is playing - may need to deactivate first")
            }
            
            try configureAudioSession()
            print("   - ✅ Audio session reactivated successfully")
            
            // Verify critical audio session properties
            print("   - 📊 Session verification: category=\(audioSession.category), inputAvailable=\(audioSession.isInputAvailable)")
            
            if !audioSession.isInputAvailable {
                print("   - ⚠️ WARNING: No audio input available after reactivation!")
                #if !targetEnvironment(simulator)
                print("   - 🔍 This might prevent recording from working properly")
                #endif
            }
            
        } catch {
            print("   - ❌ Failed to reactivate audio session: \(error)")
            print("   - 🔍 Audio session error details: \((error as NSError).domain), code: \((error as NSError).code)")
            print("   - 📊 Session state: category=\(audioSession.category), otherAudioPlaying=\(audioSession.isOtherAudioPlaying)")
            resumeSuccessful = false
            resumeError = error
            onError?(error)
        }
        
        // Resume recording if it was active and session was reactivated
        if resumeSuccessful && wasRecordingBeforeInterruption {
            do {
                print("   - 🎙️ Attempting to resume recording...")
                print("   - 📊 Pre-resume state: engine=\(audioEngine.isRunning), recording=\(isRecordingActive), url=\(recordingURL?.lastPathComponent ?? "nil")")
                
                // CRITICAL: Verify audio engine state before resume
                if !audioEngine.isRunning {
                    print("   - ⚠️ Audio engine was stopped during interruption - this is expected")
                    print("   - 🔄 Audio engine will be restarted by resumeRecording()")
                } else {
                    print("   - ✅ Audio engine still running from before interruption")
                }
                
                try resumeRecording()
                AudioStateManager.shared.startRecording()
                print("   - ✅ Recording resumed successfully")
                print("   - 📊 Post-resume state: active=\(isRecordingActive), engine=\(audioEngine.isRunning), file=\(audioFile != nil)")
                
                // Verify audio is actually flowing
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    if let self = self {
                        print("   - 🔍 Post-resume verification: recording=\(self.isRecordingActive), power=\(self.currentPower)")
                        if self.isRecordingActive && self.currentPower > -160 {
                            print("   - ✅ Audio is flowing properly after resume")
                        } else if self.isRecordingActive {
                            print("   - ⚠️ Recording active but no audio power detected - possible microphone issue")
                        } else {
                            print("   - ❌ Recording not active after resume attempt")
                        }
                    }
                }
                
            } catch {
                print("   - ❌ Failed to resume recording: \(error)")
                print("   - 🔍 Recording resume error details: \(error.localizedDescription)")
                print("   - 📊 State during failure: recording URL=\(recordingURL?.lastPathComponent ?? "nil"), audio file=\(audioFile != nil)")
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
            
            print("🟢 Resume attempt complete - all operations restored")
        } else {
            // Handle failed resume attempt
            if currentResumeAttempts < maximumAutoResumeAttempts {
                print("🔄 Resume failed, will retry in 3 seconds...")
                scheduleResumeAttempt(delaySeconds: 3.0)
            } else {
                print("🛑 All resume attempts exhausted - manual intervention required")
                
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
        print("🔄 App will resign active - preparing for background")
        // Keep audio session active for background recording
        if isRecordingActive || transcriptionEnabled {
            print("📱 Maintaining audio session for background recording/transcription")
            try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        }
    }
    
    @objc private func handleAppDidBecomeActive() {
        print("🔄 App became active - resuming from background")
        // Ensure audio session is still active
        if isRecordingActive || transcriptionEnabled {
            print("📱 Reactivating audio session from background")
            try? configureAudioSession()
        }
    }
    
    @objc private func handleAppDidEnterBackground() {
        print("🔄 App entered background")
        if isRecordingActive {
            print("🎙️ Recording continues in background...")
        }
        if transcriptionEnabled {
            print("🗣️ Transcription continues in background...")
        }
        
        // Ensure audio session stays active for background recording
        if isRecordingActive || transcriptionEnabled {
            do {
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                print("✅ Audio session maintained for background operation")
            } catch {
                print("❌ Failed to maintain audio session in background: \(error)")
                onError?(error)
            }
        }
    }
    
    @objc private func handleAppWillEnterForeground() {
        print("🔄 App will enter foreground")
        // Refresh audio session configuration
        if isRecordingActive || transcriptionEnabled {
            print("📱 Refreshing audio session for foreground")
            do {
                try configureAudioSession()
                print("✅ Audio session refreshed for foreground")
            } catch {
                print("❌ Failed to refresh audio session: \(error)")
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
        
        print("📞 Call state changed:")
        print("   - Call UUID: \(call.uuid)")
        print("   - Call active: \(isCallActive)")
        print("   - Has ended: \(call.hasEnded)")
        print("   - Previous state: \(wasCallActive)")
        
        // If call just ended and we have pending resume operations
        if wasCallActive && !isCallActive {
            print("📞 Call ended - checking for pending resume operations")
            
            if wasRecordingBeforeInterruption || wasTranscribingBeforeInterruption {
                print("📞 Call ended with pending operations - scheduling resume")
                // Give a moment for the audio session to stabilize after call ends
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.attemptResume()
                }
            }
        }
        
        // If call just started while recording/transcribing (edge case)
        if !wasCallActive && isCallActive {
            if isRecordingActive || transcriptionEnabled {
                print("📞 Call started while audio operations active - triggering interruption handling")
                handleInterruptionBegan()
            }
        }
    }
}
