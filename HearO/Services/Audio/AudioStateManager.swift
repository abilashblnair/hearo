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
        guard !isStandaloneTranscriptActive else {
            print("❌ AudioStateManager: Cannot start recording while standalone transcript is active")
            return false
        }
        
        isRecordingActive = true
        print("🎙️ AudioStateManager: Recording started")
        return true
    }
    
    func stopRecording() {
        isRecordingActive = false
        print("🛑 AudioStateManager: Recording stopped")
    }
    
    // MARK: - Standalone Transcript State Management
    
    func startStandaloneTranscript() -> Bool {
        guard !isRecordingActive else {
            print("❌ AudioStateManager: Cannot start standalone transcript while recording is active")
            return false
        }
        
        isStandaloneTranscriptActive = true
        print("🗣️ AudioStateManager: Standalone transcript started")
        return true
    }
    
    func stopStandaloneTranscript() {
        isStandaloneTranscriptActive = false
        print("🔇 AudioStateManager: Standalone transcript stopped")
    }
    
    // MARK: - State Queries
    
    var canStartRecording: Bool {
        !isStandaloneTranscriptActive
    }
    
    var canStartStandaloneTranscript: Bool {
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
