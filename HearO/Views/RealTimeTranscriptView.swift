import SwiftUI
import Speech

struct RealTimeTranscriptView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isAuthorized = false
    @State private var isRecording = false
    @State private var transcript: String = ""
    @State private var errorMessage: String?

    private let locale = Locale(identifier: "en-US") // English
    private var recognizer: SFSpeechRecognizer? { SFSpeechRecognizer(locale: locale) }

    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    private let audioStateManager = AudioStateManager.shared

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if !isAuthorized {
                    VStack(spacing: 8) {
                        Image(systemName: "mic.slash").font(.largeTitle)
                        Text("Speech permission required").font(.headline)
                        Text("Please allow speech recognition to enable live transcription.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("Request Permission") {
                            Task { await requestAuthorization() }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack {
                        // Control buttons
                        HStack {
                            Button(action: { isRecording ? stopRecognition() : startRecognition() }) {
                                HStack {
                                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                                    Text(isRecording ? "Stop" : "Start")
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(isRecording ? Color.red : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(20)
                            }
                            .disabled(recognizer?.isAvailable != true)
                        }
                        
                        // Error message
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                        }

                        // Transcript display
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Live Transcript")
                                    .font(.headline)
                                    .padding(.bottom, 4)
                                
                                Text(transcript.isEmpty ? "Tap start to begin transcription..." : transcript)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Live Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await requestAuthorization() }
        .onDisappear { stopRecognition() }
    }

    // MARK: - Authorization
    private func requestAuthorization() async {
        let speechStatus = await requestSpeechAuthorization()
        let micStatus = await requestMicrophoneAuthorization()
        await MainActor.run {
            isAuthorized = speechStatus && micStatus
            if !isAuthorized {
                errorMessage = "Both speech recognition and microphone permissions are required."
            }
        }
    }

    private func requestSpeechAuthorization() async -> Bool {
        return await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        if #available(iOS 17.0, *) {
            return await withCheckedContinuation { cont in
                AVAudioApplication.requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        } else {
            return await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
    }

    private func startRecognition() {
        guard recognizer?.isAvailable == true else { errorMessage = "Speech recognizer not available."; return }
        
        // Check for audio conflicts
        guard AudioStateManager.shared.startStandaloneTranscript() else {
            errorMessage = "Cannot start recognition: Recording is currently active. Please stop recording first."
            return
        }
        
        stopRecognition() // Clean any previous tasks
        
        do {
            // Create recognition request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            recognitionRequest?.shouldReportPartialResults = true
            
            // Start recognition task
            recognitionTask = recognizer?.recognitionTask(with: recognitionRequest!) { result, error in
                DispatchQueue.main.async {
                    if let result = result {
                        transcript = result.bestTranscription.formattedString
                    }
                    if let error = error {
                        errorMessage = "Recognition error: \(error.localizedDescription)"
                        stopRecognition()
                    }
                }
            }
            
            isRecording = true
            transcript.removeAll()
        } catch {
            errorMessage = "Failed to start recognition: \(error.localizedDescription)"
            AudioStateManager.shared.stopStandaloneTranscript()
        }
    }

    private func stopRecognition() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        
        // Update audio state
        AudioStateManager.shared.stopStandaloneTranscript()
    }
}