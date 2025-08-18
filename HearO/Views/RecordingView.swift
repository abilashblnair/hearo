import SwiftUI
import SwiftData
import UIKit

struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var di: ServiceContainer
    @Environment(\.modelContext) private var modelContext

    @State private var isRecording = false
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer? = nil
    @State private var sessionID = UUID()
    @State private var error: String?
    @State private var power: Float = -160
    @State private var lastDuration: TimeInterval = 0

    @State private var showNamePrompt = false
    @State private var nameText: String = ""
    @State private var isSaving = false
    
    // Cancel confirmation alert
    @State private var showCancelConfirmation = false

    // Real-time transcript state
    @State private var transcriptLines: [String] = []
    @State private var currentPartialText: String = ""
    @State private var transcriptPermissionGranted = false
    @State private var transcriptEnabled = false
    @State private var liveTranscriptActive = false

    // Scroll state for floating controls
    @State private var scrollOffset: CGFloat = 0
    @State private var showFloatingControls = false

    // Faster metering for smoother waveform
    private let meterTimer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()
    var onSave: (() -> Void)? = nil

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Fixed waveform section
                        VStack(spacing: 16) {
                            Text("New Recording")
                                .font(.headline)
                                .bold()
                                .padding(.top, 16)

                            // Waveform container
                            ZStack(alignment: .top) {
                                Rectangle()
                                    .fill(Color(.systemGray6))
                                    .frame(height: 280)
                                    .cornerRadius(16)

                                ReactiveScrollingWaveform(power: power, isActive: isRecording)
                                    .frame(height: 280)
                                    .padding(.horizontal, 16)

                                GeometryReader { geo in
                                    Rectangle()
                                        .fill(Color.red)
                                        .frame(width: 2, height: 280)
                                        .position(x: geo.size.width / 2, y: 140)
                                }
                                .allowsHitTesting(false)
                                .frame(height: 280)
                            }

                            // Timer
                            Text(timeString(from: elapsed, showMillis: true))
                                .font(.system(size: 36, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal)
                        .background(Color(.systemBackground))
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: ScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("scroll")).minY)
                        })

                        // Transcript section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: liveTranscriptActive ? "text.bubble.fill" : "text.bubble")
                                    .foregroundColor(liveTranscriptActive ? .green : .blue)
                                Text("Live Transcript")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Spacer()
                                
                                if !transcriptPermissionGranted {
                                    Button("Enable") {
                                        Task { await requestTranscriptPermissions() }
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                } else if !isRecording {
                                    Text("Will transcribe when recording starts")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(liveTranscriptActive ? Color.green : Color.orange)
                                            .frame(width: 6, height: 6)
                                        Text(liveTranscriptActive ? "Transcribing" : "Ready")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 20)

                            ScrollViewReader { scrollProxy in
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 8) {
                                        // Completed transcript lines
                                        ForEach(Array(transcriptLines.enumerated()), id: \.offset) { index, line in
                                            Text(line)
                                                .font(.body)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(Color(.secondarySystemBackground))
                                                .cornerRadius(8)
                                                .id("line-\(index)")
                                        }

                                        // Current partial text
                                        if !currentPartialText.isEmpty {
                                            Text(currentPartialText)
                                                .font(.body)
                                                .foregroundColor(.secondary)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(Color(.tertiarySystemBackground))
                                                .cornerRadius(8)
                                                .id("partial")
                                        }

                                        if transcriptLines.isEmpty && currentPartialText.isEmpty && transcriptPermissionGranted {
                                            VStack(spacing: 8) {
                                                Image(systemName: liveTranscriptActive ? "mic.circle.fill" : "mic.circle")
                                                    .font(.system(size: 40))
                                                    .foregroundColor(liveTranscriptActive ? .green : .secondary)
                                                Text(liveTranscriptActive ? "Listening for speech..." : (isRecording ? "Transcription starting..." : "Ready to transcribe"))
                                                    .font(.body)
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(.top, 40)
                                        }

                                        if !transcriptPermissionGranted {
                                            VStack(spacing: 12) {
                                                Image(systemName: "exclamationmark.triangle")
                                                    .font(.system(size: 32))
                                                    .foregroundColor(.orange)
                                                Text("Microphone and Speech Recognition permissions required for live transcript")
                                                    .font(.body)
                                                    .multilineTextAlignment(.center)
                                                    .foregroundColor(.secondary)
                                                Button("Grant Permissions") {
                                                    Task { await requestTranscriptPermissions() }
                                                }
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(Color.blue)
                                                .foregroundColor(.white)
                                                .cornerRadius(8)
                                            }
                                            .padding(.top, 20)
                                        }
                                    }
                                }
                                .frame(minHeight: 200)
                                .onChange(of: transcriptLines.count) { _, _ in
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        scrollProxy.scrollTo("line-\(transcriptLines.count - 1)", anchor: .bottom)
                                    }
                                }
                                .onChange(of: currentPartialText) { _, newValue in
                                    if !newValue.isEmpty {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            scrollProxy.scrollTo("partial", anchor: .bottom)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .background(Color(.systemGroupedBackground))
                        .padding(.bottom, 120) // Space for controls
                    }
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFloatingControls = value < -100
                    }
                }
            }

            // Floating controls when scrolled
            if showFloatingControls {
                VStack {
                    HStack(spacing: 12) {
                        Button(action: { togglePauseResume() }) {
                            Image(systemName: isRecording ? "pause.fill" : "play.fill")
                                .font(.title2)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.ultraThinMaterial))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(isRecording ? "Recording" : "Paused")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(timeString(from: elapsed))
                                .font(.caption.monospacedDigit())
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button(role: .destructive, action: { Task { await stopAndPrompt() } }) {
                            Image(systemName: "stop.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                        }
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.ultraThinMaterial))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .cornerRadius(25)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 60)
            }
            
            // Saving overlay
            if isSaving {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Saving recording...")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 0.5))
                }
            }
        }
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom) {
            if !showFloatingControls {
                // Bottom controls (when not scrolled)
                HStack(spacing: 12) {
                    Button(action: { togglePauseResume() }) {
                        HStack(spacing: 8) {
                            Image(systemName: isRecording ? "pause.fill" : "play.fill")
                            Text(isRecording ? "Pause" : "Resume")
                        }
                        .font(.system(size: 18, weight: .semibold))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    }

                    Button(role: .destructive, action: { Task { await stopAndPrompt() } }) {
                        HStack(spacing: 8) {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                        .font(.system(size: 18, weight: .semibold))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                        .foregroundColor(.red)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
        }
        .onAppear {
            // Set up audio service callbacks
            setupAudioCallbacks()
            
            Task {
                // First request permissions for transcription
                await requestTranscriptPermissions()
                // Then start or attach to recording session
                await attachOrStart()
            }
        }
        .onDisappear {
            stopTimers()
            
            // IMPORTANT: Don't disable transcription when view disappears!
            // Transcription should continue in background if recording is active
            // Only disable transcription when user explicitly stops it or stops recording
            
            // Only deactivate audio session if no recording is active
            di.audio.deactivateSessionIfNeeded()
        }
        .onReceive(meterTimer) { _ in
            guard isRecording else { return }
            di.audio.updateMeters()
            power = di.audio.currentPower
        }
        .sensoryFeedback(.success, trigger: showNamePrompt)
        .alert("Error", isPresented: .constant(error != nil), actions: {
            Button("OK", role: .cancel) { error = nil }
        }, message: {
            Text(error ?? "")
        })
        .alert("Name your recording", isPresented: $showNamePrompt) {
            TextField("Enter a title", text: $nameText)
            Button("Save") { saveNamedRecording() }
            Button("Cancel", role: .cancel) { showNamePrompt = false }
        }
        .alert("Stop Recording?", isPresented: $showCancelConfirmation) {
            Button("Continue in Background") {
                // Continue recording in background and dismiss
                dismiss()
            }
            Button("Stop Recording", role: .destructive) {
                // Stop recording and dismiss
                Task { await forceStopRecording() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Do you want to continue recording in the background or stop the recording?")
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { 
                    if isRecording || di.audio.isSessionActive {
                        showCancelConfirmation = true 
                    } else {
                        dismiss()
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }
        }
        } // NavigationView closing brace
    }

    private var defaultTitle: String { "Session " + Date.now.formatted(date: .abbreviated, time: .shortened) }

    // MARK: - Transcript Functions
    
    private func setupAudioCallbacks() {
        // Set up transcript update callback if available
        if let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl {
            unifiedService.onTranscriptUpdate = { text, isFinal in
                DispatchQueue.main.async {
                    if isFinal {
                        // Add to completed lines and clear partial
                        if !text.isEmpty {
                            transcriptLines.append(text)
                        }
                        currentPartialText = ""
                    } else {
                        // Update partial text
                        currentPartialText = text
                    }
                }
            }
            
            // Set up error handling
            unifiedService.onError = { error in
                DispatchQueue.main.async {
                    self.error = "Audio error: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func requestTranscriptPermissions() async {
        do {
            if let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl {
                try await unifiedService.requestSpeechPermission()
                transcriptPermissionGranted = true
            } else {
                self.error = "Live transcription not available with this audio service"
            }
        } catch {
            self.error = "Speech recognition permission denied: \(error.localizedDescription)"
            transcriptPermissionGranted = false
        }
    }
    
    @MainActor
    private func toggleLiveTranscript() async {
        guard let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl else {
            self.error = "Live transcription not available with this audio service"
            return
        }
        
        do {
            if transcriptEnabled {
                unifiedService.disableTranscription()
                transcriptEnabled = false
                liveTranscriptActive = false
            } else {
                try await unifiedService.enableTranscription()
                transcriptEnabled = true
                liveTranscriptActive = true
            }
        } catch {
            self.error = "Failed to toggle transcription: \(error.localizedDescription)"
        }
    }



    // MARK: - Recording Functions

    private func attachOrStart() async {
        if di.audio.isSessionActive {
            print("🔗 Attaching to existing recording session...")
            
            // Restore basic recording state
            isRecording = di.audio.isRecording
            elapsed = di.audio.currentTime
            if let url = di.audio.currentRecordingURL {
                let base = url.deletingPathExtension().lastPathComponent
                if let uid = UUID(uuidString: base) { sessionID = uid }
            }
            startTimers()
            
            // Restore transcription state if it was already active
            if let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl {
                if unifiedService.isTranscriptionActive {
                    print("🗣️ Transcription was already active, restoring UI state...")
                    transcriptEnabled = true
                    liveTranscriptActive = true

                    
                    print("✅ Live transcription UI state restored")
                } else {
                    print("📝 No active transcription detected")
                }
            }
            
            print("✅ Successfully attached to existing session (Recording: \(isRecording), Transcription: \(transcriptEnabled))")
        } else {
            await startRecording()
        }
    }

    func startRecording() async {
        do {
            sessionID = UUID()
            let url = try AudioFileStore.url(for: sessionID)
            try await di.audio.requestMicPermission()
            
            // Start recording with native transcription if permissions are granted
            if transcriptPermissionGranted, let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl {
                try await unifiedService.startRecordingWithNativeTranscription(to: url)
                transcriptEnabled = true
                liveTranscriptActive = true
            } else {
                // Fall back to basic recording
                try di.audio.startRecording(to: url)
            }
            
            isRecording = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            elapsed = 0
            startTimers()
            
        } catch { 
            self.error = error.localizedDescription 
        }
    }

    func togglePauseResume() {
        do {
            if isRecording {
                try di.audio.pauseRecording(); isRecording = false
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                // Optionally pause speech recognition when recording is paused
                // (speech recognition can continue even when recording is paused)
            } else {
                try di.audio.resumeRecording(); isRecording = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } catch { 
            self.error = "Recording operation failed: \(error.localizedDescription)"
            print("❌ Pause/Resume error: \(error)")
        }
    }

    func stopAndPrompt() async {
        do {
            isSaving = true
            let duration = try di.audio.stopRecording()
            isRecording = false
            stopTimers()
            
            // Clean up transcription if active
            if let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl {
                unifiedService.disableTranscription()
            }
            transcriptEnabled = false
            liveTranscriptActive = false
            
            lastDuration = duration
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            
            // Small delay to ensure smooth transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.isSaving = false
                self.showNamePrompt = true
            }
        } catch { 
            self.isSaving = false
            self.error = error.localizedDescription 
        }
    }
    
    func forceStopRecording() async {
        do {
            isSaving = true
            _ = try di.audio.stopRecording()
            isRecording = false
            stopTimers()
            
            // Clean up transcription if active
            if let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl {
                unifiedService.disableTranscription()
            }
            transcriptEnabled = false
            liveTranscriptActive = false
            
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            
            // Small delay to ensure smooth transition then dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.isSaving = false
                self.dismiss()
            }
        } catch { 
            self.isSaving = false
            self.error = error.localizedDescription 
        }
    }

    func saveNamedRecording() {
        do {
            let title = nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultTitle : nameText
            _ = try AudioFileStore.url(for: sessionID)
            // Store a relative path under Documents to avoid container UUID issues across launches
            let relativePath = "audio/\(sessionID.uuidString).m4a"
            let rec = Recording(id: sessionID, title: title, createdAt: Date(), audioURL: relativePath, duration: lastDuration)
            try RecordingDataStore(context: modelContext).saveRecording(rec)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            NotificationCenter.default.post(name: .didSaveRecording, object: nil)
            onSave?(); dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func startTimers() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
            if isRecording { elapsed += 0.01 }
        }
    }

    func stopTimers() {
        timer?.invalidate(); timer = nil
    }

    func timeString(from interval: TimeInterval, showMillis: Bool = false) -> String {
        let totalSeconds = Int(interval)
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if showMillis {
            let millis = Int((interval - Double(totalSeconds)) * 100)
            return String(format: "%02d:%02d.%02d", minutes, seconds, millis)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Supporting Views and Preferences

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// Reactive, speech-driven scrolling waveform
struct ReactiveScrollingWaveform: View {
    let power: Float // -160..0 dB
    var isActive: Bool = true
    @State private var smoothed: CGFloat = 0.05
    @State private var samples: [CGFloat] = []

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let barWidth: CGFloat = 3
                    let spacing: CGFloat = 2
                    let capacity = max(16, Int(size.width / (barWidth + spacing)))
                    let midY = size.height / 2

                    let shading = GraphicsContext.Shading.linearGradient(
                        Gradient(colors: [Color.red.opacity(0.9), Color.orange.opacity(0.9)]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: size.width, y: 0)
                    )

                    let slice = samples.suffix(capacity)
                    for (i, amp) in slice.enumerated() {
                        let x = size.width - CGFloat(slice.count - i) * (barWidth + spacing)
                        let h = max(6, amp * size.height)
                        let rectTop = CGRect(x: x, y: midY - h/2, width: barWidth, height: h/2)
                        let rectBottom = CGRect(x: x, y: midY, width: barWidth, height: h/2)
                        context.fill(Path(roundedRect: rectTop, cornerRadius: 1.5), with: shading)
                        context.fill(Path(roundedRect: rectBottom, cornerRadius: 1.5), with: shading)
                    }
                }
                .onChange(of: power) { _, newValue in
                    let linear = max(0, min(1, CGFloat(pow(10, newValue / 20))))
                    smoothed = smoothed * 0.85 + linear * 0.15
                }
                .onChange(of: timeline.date) { _, _ in
                    guard isActive else { return }
                    let jitter = CGFloat.random(in: -0.02...0.02)
                    let amp = max(0.04, min(1.0, smoothed + jitter))
                    samples.append(amp)
                    let capEst = max(16, Int(geo.size.width / (3 + 2)))
                    if samples.count > capEst { samples.removeFirst(samples.count - capEst) }
                }
            }
        }
    }
}

