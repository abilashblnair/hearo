import SwiftUI
import AVFoundation

struct AAIStreamingTranscriptView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isAuthorized = false
    @State private var isStreaming = false
    @State private var transcript: String = ""
    @State private var errorMessage: String?

    private let sampleRate: Double = 16_000
    private let apiBase = URL(string: "wss://streaming.assemblyai.com/v3/ws")!
    private let audioStateManager = AudioStateManager.shared

    private var targetFormat: AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)
    }
    @State private var converter: AVAudioConverter?

    @State private var webSocket: URLSessionWebSocketTask?
    private let urlSession = URLSession(configuration: .default)

    var body: some View {
        NavigationStack {
            if UIDevice.current.userInterfaceIdiom == .pad {
                // iPad centered layout
                GeometryReader { geometry in
                    HStack {
                        Spacer()
                        
                        VStack(alignment: .leading, spacing: 16) {
                            ScrollView {
                                Text(transcript.isEmpty ? (isStreaming ? "Listening…" : "Tap Start to begin streaming") : transcript)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                            }
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                            if let errorMessage { Text(errorMessage).foregroundColor(.red).font(.footnote) }
                            Spacer()
                        }
                        .padding(24)
                        .frame(maxWidth: min(geometry.size.width * 0.8, 900))
                        
                        Spacer()
                    }
                }
            } else {
                // iPhone layout
                VStack(alignment: .leading, spacing: 16) {
                    ScrollView {
                        Text(transcript.isEmpty ? (isStreaming ? "Listening…" : "Tap Start to begin streaming") : transcript)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    if let errorMessage { Text(errorMessage).foregroundColor(.red).font(.footnote) }
                    Spacer()
                }
                .padding(16)
            }
        }
        .navigationTitle("Live Transcript (AAI)")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button(isStreaming ? "Stop" : "Start") { toggle() }.disabled(!isAuthorized)
            }
        }
        .onAppear { Task { await preparePermissions() } }
        .onDisappear { stopStreaming() }
    }

    private func toggle() {
        isStreaming ? stopStreaming() : startStreaming()
    }

    private func preparePermissions() async {
        let granted = await requestMicrophonePermission()
        await MainActor.run { isAuthorized = granted }
    }

    private func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await withCheckedContinuation { cont in
                AVAudioApplication.requestRecordPermission { granted in cont.resume(returning: granted) }
            }
        } else {
            return await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in cont.resume(returning: granted) }
            }
        }
    }

    private func startStreaming() {
        // Check for audio conflicts
        guard AudioStateManager.shared.startStandaloneTranscript() else {
            errorMessage = "Cannot start streaming: Recording is currently active. Please stop recording first."
            return
        }
        
        let key = Secrets.assemblyAIKey
        guard key.isEmpty == false else {
            errorMessage = "Missing ASSEMBLYAI_API_KEY in Info.plist/UserDefaults."
            AudioStateManager.shared.stopStandaloneTranscript()
            return
        }

        do {
            // Set up converter for audio format conversion
            let inputFormat = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)!
            guard let targetFormat = targetFormat else {
                throw NSError(domain: "AudioFormat", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create target audio format"])
            }
            
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
            
            // Set up WebSocket
            let request = URLRequest(url: apiBase)
            webSocket = urlSession.webSocketTask(with: request)
            webSocket?.resume()
            
            // Send initial configuration
            let config: [String: Any] = [
                "sample_rate": Int(sampleRate),
                "word_boost": [],
                "encoding": "pcm_s16le"
            ]
            let configData = try JSONSerialization.data(withJSONObject: config)
            webSocket?.send(.data(configData), completionHandler: { error in
                if let error = error {
                    DispatchQueue.main.async {
                        errorMessage = "WebSocket config error: \(error.localizedDescription)"
                    }
                }
            })
            
            // Audio streaming not supported in conflict prevention mode
            // Show message that recording with native transcription should be used instead
            isStreaming = true
            errorMessage = nil
            transcript = ""
            
            // Start listening for WebSocket messages
            listenForMessages()
            
        } catch {
            errorMessage = "Failed to start streaming: \(error.localizedDescription)"
            AudioStateManager.shared.stopStandaloneTranscript()
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter = converter,
              let targetFormat = targetFormat else { return }
        
        let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: buffer.frameCapacity)!
        
        var error: NSError?
        let status = converter.convert(to: targetBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        guard status != .error, error == nil else {
            return
        }
        
        // Convert to Data and send
        if let data = targetBuffer.toData() {
            webSocket?.send(.data(data), completionHandler: { error in
                if error != nil {
                }
            })
        }
    }

    private func stopStreaming() {
        // Send termination message
        webSocket?.send(.data(Data([0x00, 0x00, 0x00, 0x00])), completionHandler: { _ in })
        
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        converter = nil
        isStreaming = false
        
        AudioStateManager.shared.stopStandaloneTranscript()
    }

    private func listenForMessages() {
        webSocket?.receive { result in
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let text = json["text"] as? String, !text.isEmpty {
                        DispatchQueue.main.async {
                            transcript = text
                        }
                    }
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let transcriptText = json["text"] as? String, !transcriptText.isEmpty {
                        DispatchQueue.main.async {
                            transcript = transcriptText
                        }
                    }
                @unknown default:
                    break
                }
                // Continue listening
                listenForMessages()
            case .failure(let error):
                DispatchQueue.main.async {
                    errorMessage = "WebSocket error: \(error.localizedDescription)"
                    stopStreaming()
                }
            }
        }
    }
}

// MARK: - AVAudioPCMBuffer Extension
private extension AVAudioPCMBuffer {
    func toData() -> Data? {
        guard let channelData = int16ChannelData else { return nil }
        let channelDataValue = channelData.pointee
        let dataSize = Int(frameLength * 2) // 2 bytes per Int16 sample
        return Data(bytes: channelDataValue, count: dataSize)
    }
}