import Foundation

/// Global audio state coordinator to prevent conflicts between different audio components
final class AudioStateManager: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = AudioStateManager()
    
    // MARK: - Audio State
    @Published var isRecordingActive = false
    @Published var isStandaloneTranscriptActive = false
    
    private init() {}
    
    // MARK: - Recording State Management
    
    func startRecording() -> Bool {
        // Allow recording to start even if transcript is active
        // We want simultaneous recording and transcription
        isRecordingActive = true
        return true
    }
    
    func stopRecording() {
        isRecordingActive = false
    }
    
    // MARK: - Standalone Transcript State Management
    
    func startStandaloneTranscript() -> Bool {
        guard !isRecordingActive else {
            return false
        }
        
        isStandaloneTranscriptActive = true
        return true
    }
    
    func stopStandaloneTranscript() {
        isStandaloneTranscriptActive = false
    }
    
    // MARK: - State Queries
    
    var canStartRecording: Bool {
        // Recording can start unless standalone transcript (AAI streaming) is active
        !isStandaloneTranscriptActive
    }
    
    var canStartStandaloneTranscript: Bool {
        // Standalone transcript (AAI streaming) cannot start if recording is active
        !isRecordingActive
    }
    
    var audioConflictMessage: String {
        if isRecordingActive && isStandaloneTranscriptActive {
            return "Audio conflict: Both recording and transcript are active"
        } else if isRecordingActive {
            return "Recording is active - standalone transcript blocked"
        } else if isStandaloneTranscriptActive {
            return "Standalone transcript is active - recording blocked"
        } else {
            return "No audio conflicts"
        }
    }
}
