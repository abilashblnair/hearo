import SwiftUI
import SwiftData
import UIKit
import Speech

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

    @State private var showSavePopup = false
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
    
    // Interruption handling state
    @State private var isInterrupted = false
    @State private var showResumePrompt = false
    @State private var interruptionType: String = ""
    @State private var resumeAttempts = 0
    @State private var maxResumeAttempts = 3

    // Faster metering for smoother waveform
    private let meterTimer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()
    var onSave: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Custom close button overlay (always visible)
                VStack {
                    HStack {
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
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(.ultraThinMaterial))
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        }
                        .padding(.leading, 16)

                        Spacer()
                    }
                    
                    Spacer()
                }
                .zIndex(1000)
                
                Group {
                    if UIDevice.current.userInterfaceIdiom == .pad {
                    // iPad centered layout
                    GeometryReader { geometry in
                        HStack {
                            Spacer()

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
                                                    .frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 350 : 280)
                                                    .cornerRadius(16)

                                                ReactiveScrollingWaveform(power: power, isActive: isRecording)
                                                    .frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 350 : 280)
                                                    .padding(.horizontal, 16)

                                                GeometryReader { geo in
                                                    Rectangle()
                                                        .fill(Color.red)
                                                        .frame(width: 2, height: UIDevice.current.userInterfaceIdiom == .pad ? 350 : 280)
                                                        .position(x: geo.size.width / 2, y: UIDevice.current.userInterfaceIdiom == .pad ? 175 : 140)
                                                }
                                                .allowsHitTesting(false)
                                                .frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 350 : 280)
                                            }

                                            // Timer
                                            Text(timeString(from: elapsed, showMillis: true))
                                                .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 42 : 36, weight: .bold, design: .monospaced))
                                                .foregroundColor(.primary)
                                        }
                                        .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 40 : 16)
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
                                                    .onAppear {
                                                        print("📝 DEBUG: Showing 'listening' state - lines:\(transcriptLines.count), partial:'\(currentPartialText)', permission:\(transcriptPermissionGranted), liveActive:\(liveTranscriptActive)")
                                                    }
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
                            .frame(maxWidth: min(geometry.size.width * 0.85, 900))

                            Spacer()
                        }
                    }
                    } else {
                        // iPhone layout
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
                                .padding(.horizontal, 16)
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
                                                    .onAppear {
                                                        print("📝 DEBUG: Showing 'listening' state - lines:\(transcriptLines.count), partial:'\(currentPartialText)', permission:\(transcriptPermissionGranted), liveActive:\(liveTranscriptActive)")
                                                    }
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
                    }
                }

            }

            // Modern floating controls when scrolled
            if showFloatingControls {
                VStack {
                    HStack(spacing: 16) {
                        // Pause/Resume Button
                        Button(action: { 
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            togglePauseResume() 
                        }) {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 48, height: 48)
                                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                                
                                Circle()
                                    .stroke(isRecording ? Color.orange.opacity(0.4) : Color.green.opacity(0.4), lineWidth: 1.5)
                                    .frame(width: 48, height: 48)
                                
                                Image(systemName: isRecording ? "pause.fill" : "play.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(isRecording ? .orange : .green)
                                    .contentTransition(.symbolEffect(.replace.downUp))
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(isInterrupted ? Color.yellow : (isRecording ? Color.red : Color.orange))
                                    .frame(width: 6, height: 6)
                                    .scaleEffect(isRecording ? 1.2 : 1.0)
                                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isRecording)
                                
                                Text(isInterrupted ? "Call in progress" : (isRecording ? "Recording" : "Paused"))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(timeString(from: elapsed))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Stop Button
                        Button(role: .destructive, action: { 
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            Task { await stopAndPrompt() } 
                        }) {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 44, height: 44)
                                    .shadow(color: .red.opacity(0.2), radius: 5, x: 0, y: 2)
                                
                                Circle()
                                    .stroke(Color.red.opacity(0.4), lineWidth: 1)
                                    .frame(width: 44, height: 44)
                                
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.red)
                                    .frame(width: 12, height: 12)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 28)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
                    )

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
                // Modern bottom controls
                VStack(spacing: 16) {
                    // Recording status indicator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(isInterrupted ? Color.yellow : (isRecording ? Color.red : Color.orange))
                            .frame(width: 8, height: 8)
                            .scaleEffect(isRecording ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isRecording)
                        
                        Text(isInterrupted ? "Call in progress" : (isRecording ? "Recording" : "Paused"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(timeString(from: elapsed))
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    
                    // Control buttons
                    HStack(spacing: 32) {
                        // Pause/Resume Button
                        Button(action: { 
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            togglePauseResume() 
                        }) {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 72, height: 72)
                                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                                
                                Circle()
                                    .stroke(isRecording ? Color.orange.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 2)
                                    .frame(width: 72, height: 72)
                                
                                Image(systemName: isRecording ? "pause.fill" : "play.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(isRecording ? .orange : .green)
                                    .contentTransition(.symbolEffect(.replace.downUp))
                            }
                        }
                        .scaleEffect(isRecording ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isRecording)
                        
                        // Stop Button
                        Button(role: .destructive, action: { 
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            Task { await stopAndPrompt() } 
                        }) {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 64, height: 64)
                                    .shadow(color: .red.opacity(0.2), radius: 6, x: 0, y: 3)
                                
                                Circle()
                                    .stroke(Color.red.opacity(0.3), lineWidth: 1.5)
                                    .frame(width: 64, height: 64)
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.red)
                                    .frame(width: 16, height: 16)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -2)
                )
                .padding(.horizontal, 16)
            }
        }
        .onAppear {
            // Check actual system permissions to restore transcriptPermissionGranted properly
            Task {
                let speechAuthStatus = SFSpeechRecognizer.authorizationStatus()
                let isPermissionGranted = speechAuthStatus == .authorized
                
                if isPermissionGranted && !transcriptPermissionGranted {
                    await MainActor.run {
                        transcriptPermissionGranted = true
                    }
                }
            }
            
            // Set up audio service callbacks
            setupAudioCallbacks()
            
            // Set up notification action observers
            setupNotificationObservers()
            
            Task {
                // Request notification permissions
                _ = await di.notifications.requestPermissions()
                
                // First request permissions for transcription if not already granted
                if !transcriptPermissionGranted {
                    await requestTranscriptPermissions()
                }
                
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
        .sensoryFeedback(.success, trigger: showSavePopup)
        .alert("Error", isPresented: .constant(error != nil), actions: {
            Button("OK", role: .cancel) { error = nil }
        }, message: {
            Text(error ?? "")
        })
        .overlay {
            if showSavePopup {
                SaveRecordingPopupView(
                    duration: lastDuration,
                    onSave: { title, notes in
                        saveNamedRecording(title: title, notes: notes)
                    },
                    onCancel: {
                        showSavePopup = false
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .center)))
                .zIndex(1000)
            }
        }
        .alert("Stop Recording?", isPresented: $showCancelConfirmation) {
            Button("Continue in Background") {
                // Continue recording in background and dismiss
                dismiss()
            }
            Button("Stop Recording", role: .destructive) {
                // Stop recording and dismiss
                Task { await stopAndPrompt() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Do you want to continue recording in the background or stop the recording?")
        }
        .alert("Resume Recording?", isPresented: $showResumePrompt) {
            Button("Resume Recording") {
                manualResumeRecording()
            }
            Button("Stop Recording", role: .destructive) {
                Task { await stopAndPrompt() }
            }
            Button("Not Now", role: .cancel) { 
                showResumePrompt = false
            }
        } message: {
            Text("Your \(interruptionType) has ended. Would you like to resume recording or stop and save the current session?")
        }
        .navigationBarHidden(true)
        } // NavigationStack closing brace

    private var defaultTitle: String { "Session " + Date.now.formatted(date: .abbreviated, time: .shortened) }

    // MARK: - Notification Functions
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .stopRecordingFromNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await self.stopAndPrompt()
            }
        }
    }
    
    // MARK: - Transcript Functions
    
    private func setupAudioCallbacks() {
        // Set up transcript update callback if available
        if let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl {
            // ✅ Ensure transcript permission is granted for proper UI display
            if transcriptEnabled {
                transcriptPermissionGranted = true
            }
            
            setupTranscriptCallback(unifiedService)
            
            // Set up error handling
            unifiedService.onError = { error in
                DispatchQueue.main.async {
                    self.error = "Audio error: \(error.localizedDescription)"
                }
            }
            
            // Set up interruption handling callbacks
            unifiedService.onInterruptionBegan = {
                DispatchQueue.main.async {
                    self.handleInterruptionBegan()
                }
            }
            
            unifiedService.onRecordingPaused = {
                DispatchQueue.main.async {
                    self.handleRecordingPaused()
                }
            }
            
            unifiedService.onRecordingResumed = {
                DispatchQueue.main.async {
                    self.handleRecordingResumed()
                }
            }
            
            unifiedService.onAutoResumeAttemptFailed = { attempts, error in
                DispatchQueue.main.async {
                    self.handleAutoResumeAttemptFailed(attempts: attempts, error: error)
                }
            }
            
            // Set up transcript cache restoration callback
            unifiedService.onTranscriptCacheRestored = { cachedLines, cachedPartial in
                DispatchQueue.main.async {
                    self.restoreTranscriptCache(lines: cachedLines, partial: cachedPartial)
                }
            }
            
            // Configure interruption handling for optimal user experience
            unifiedService.configureInterruptionHandling(
                pauseOnInterruption: true,
                autoResumeAfterInterruption: true,
                maxAutoResumeAttempts: maxResumeAttempts
            )
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


    
    private func setupTranscriptCallback(_ unifiedService: UnifiedAudioRecordingServiceImpl) {
        
        unifiedService.onTranscriptUpdate = { text, isFinal in
            DispatchQueue.main.async {
                if isFinal {
                    // Final result - add completed segment to transcript lines
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.transcriptLines.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    self.currentPartialText = ""
                } else {
                    // Partial result - show current recognition attempt
                    self.currentPartialText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // Ensure UI state is properly set when we receive transcript updates
                if !self.transcriptPermissionGranted {
                    self.transcriptPermissionGranted = true
                }
                if !self.liveTranscriptActive {
                    self.liveTranscriptActive = true
                }
            }
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
                    transcriptPermissionGranted = true  // ✅ CRITICAL: Set permission if transcription is active
                    
                    print("✅ Live transcription UI state restored with permissions")
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
            // Randomly show ad (1 in 3 chance) before recording
        if Int.random(in: 1...3) == 1, di.adManager.isAdReady, let rootVC = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController {
            di.adManager.presentInterstitial(from: rootVC) { _ in
                // Continue with recording after ad
                print("🎬 Recording ad completed - starting recording")
            }
        }
            
            sessionID = UUID()
            let url = try AudioFileStore.url(for: sessionID)
            try await di.audio.requestMicPermission()
            
            // Start recording with native transcription if permissions are granted
            if transcriptPermissionGranted, let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl {
                try await unifiedService.startRecordingWithNativeTranscription(to: url)
                transcriptEnabled = true
                liveTranscriptActive = true
                // Ensure callback is set up for new recordings
                setupTranscriptCallback(unifiedService)
            } else {
                // Fall back to basic recording
                try di.audio.startRecording(to: url)
            }
            
            isRecording = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            elapsed = 0
            startTimers()
            
            // Start notification updates
            di.notifications.startRecordingNotifications(title: "New Recording")
            
        } catch { 
            self.error = error.localizedDescription 
        }
    }

    func togglePauseResume() {
        if isRecording {
            // Pause both recording and transcription
            do {
                try di.audio.pauseRecording()
                isRecording = false
                
                // Pause transcription if active
                if let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl, transcriptEnabled {
                    unifiedService.disableTranscription()
                    liveTranscriptActive = false
                }
                
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch { 
                self.error = "Recording operation failed: \(error.localizedDescription)"
            }
        } else {
            // Resume both recording and transcription
            Task {
                do {
                    try di.audio.resumeRecording()
                    isRecording = true
                    
                    // Resume transcription if it was enabled
                    if let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl, transcriptEnabled {
                        try await unifiedService.enableTranscription()
                        liveTranscriptActive = true
                        // Re-establish callback after resume
                        setupTranscriptCallback(unifiedService)
                    }
                    
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } catch { 
                    self.error = "Recording operation failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func stopAndPrompt() async {
        do {
            isSaving = true
            let duration = try di.audio.stopRecording()
            isRecording = false
            stopTimers()
            
            // Stop notification updates
            di.notifications.stopRecordingNotifications()
            
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
                self.showSavePopup = true
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
            
            // Stop notification updates
            di.notifications.stopRecordingNotifications()
            
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

    func saveNamedRecording(title: String, notes: String?) {
        do {
            _ = try AudioFileStore.url(for: sessionID)
            // Store a relative path under Documents to avoid container UUID issues across launches
            let relativePath = "audio/\(sessionID.uuidString).m4a"
            let rec = Recording(id: sessionID, title: title, createdAt: Date(), audioURL: relativePath, duration: lastDuration, notes: notes)
            try RecordingDataStore(context: modelContext).saveRecording(rec)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            NotificationCenter.default.post(name: .didSaveRecording, object: nil)
            // Stop notification updates
            di.notifications.showRecordingSuccessNotification()
            showSavePopup = false
            onSave?(); dismiss()
        } catch {
            self.error = error.localizedDescription
            showSavePopup = false
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
    
    // MARK: - Interruption Handling
    
    private func handleInterruptionBegan() {
        if !isInterrupted {
            // Cache current transcript state before interruption
            if let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl {
                unifiedService.cacheTranscript(lines: transcriptLines, partial: currentPartialText)
            }
            
            isInterrupted = true
            interruptionType = "phone call"
            togglePauseResume()

            // Provide haptic feedback
            UINotificationFeedbackGenerator().notificationOccurred(.warning)

            // Show visual feedback
            withAnimation(.easeInOut(duration: 0.3)) {
                // UI will automatically update based on isInterrupted state
            }
        }
    }
    
    private func handleRecordingPaused() {
        isRecording = false
        
        // Provide haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        // Update UI state
        withAnimation(.easeInOut(duration: 0.2)) {
            // Recording state updated, UI will reflect pause
        }
    }
    
    private func handleRecordingResumed() {
        // Synchronize with actual audio service state
        if let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl {
            // Update recording state
            let serviceRecording = unifiedService.isRecording
            let serviceTranscription = unifiedService.isTranscriptionActive
            let serviceTime = unifiedService.currentTime
            
            // Update UI state to match service
            isRecording = serviceRecording
            elapsed = serviceTime
            
            // Restore transcription state if it was active before interruption
            if unifiedService.wasTranscriptionActiveBeforeInterruption {
                transcriptEnabled = true
                liveTranscriptActive = true
                transcriptPermissionGranted = true
                
                // Re-establish transcript callback after resume
                setupTranscriptCallback(unifiedService)
                
                // Force UI refresh to show existing transcript content
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        // UI state variables updated, will trigger refresh
                    }
                }
            } else if serviceTranscription {
                // Fallback: if service reports transcription active but we didn't track it
                transcriptEnabled = true
                liveTranscriptActive = true
                transcriptPermissionGranted = true
                setupTranscriptCallback(unifiedService)
            }
        }
        
        // Reset interruption state
        isInterrupted = false
        showResumePrompt = false
        resumeAttempts = 0
        
        // Restart timers to ensure UI updates properly
        if timer == nil && isRecording {
            startTimers()
        }
        
        // Resume notification updates
        if isRecording {
            di.notifications.startRecordingNotifications(title: "Recording Resumed")
        }
        
        // Provide haptic feedback
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        // Update UI state with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            // State variables already updated above, animation will reflect changes
        }
    }
    
    private func handleAutoResumeAttemptFailed(attempts: Int, error: Error) {
        resumeAttempts = attempts
        
        // Show resume prompt to user
        withAnimation(.easeInOut(duration: 0.3)) {
            showResumePrompt = true
        }
        
        // Provide haptic feedback
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    
    private func manualResumeRecording() {
        if let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl {
            unifiedService.forceResumeAfterInterruption()
            
            // Give a small delay for the audio service to process the resume
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.syncStateAfterResume()
            }
        }
        
        // Provide immediate feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func syncStateAfterResume() {
        guard let unifiedService = di.audio as? UnifiedAudioRecordingServiceImpl else { return }
        
        // Update recording state from audio service
        let wasRecordingBefore = unifiedService.wasRecordingActiveBeforeInterruption
        let wasTranscribingBefore = unifiedService.wasTranscriptionActiveBeforeInterruption
        
        // Update recording state
        isRecording = unifiedService.isRecording
        elapsed = unifiedService.currentTime
        
        // Reset interruption state
        isInterrupted = false
        showResumePrompt = false
        resumeAttempts = 0
        
        // Restore transcription state if it was active before interruption
        if wasTranscribingBefore {
            if unifiedService.isTranscriptionActive {
                // Transcription is already active, just restore UI state
                transcriptEnabled = true
                liveTranscriptActive = true
                transcriptPermissionGranted = true
                setupTranscriptCallback(unifiedService)
                
                // Force UI refresh to display transcript content properly
                withAnimation(.easeInOut(duration: 0.2)) {
                    // State variables updated, will trigger proper display
                }
            } else {
                // Transcription was active before but isn't now - restart it
                Task {
                    do {
                        try await unifiedService.enableTranscription()
                        await MainActor.run {
                            self.transcriptEnabled = true
                            self.liveTranscriptActive = true
                            self.transcriptPermissionGranted = true
                            self.setupTranscriptCallback(unifiedService)
                            
                            // Force UI refresh after manual restart
                            withAnimation(.easeInOut(duration: 0.2)) {
                                // State variables updated
                            }
                        }
                    } catch {
                        await MainActor.run {
                            self.error = "Failed to resume transcription: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
        
        // Restart timers if needed
        if timer == nil && isRecording {
            startTimers()
        }
        
        // Resume notifications
        if isRecording {
            di.notifications.startRecordingNotifications(title: "Recording Resumed")
        }
    }
    
    // MARK: - Transcript Cache Management
    
    private func restoreTranscriptCache(lines: [String], partial: String) {
        transcriptLines = lines
        currentPartialText = partial
        
        // Force UI refresh to show restored transcript
        withAnimation(.easeInOut(duration: 0.3)) {
            // State variables updated, UI will refresh
        }
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

} // RecordingView struct closing brace

