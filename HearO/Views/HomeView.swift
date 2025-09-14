import SwiftUI

struct HomeView: View {
    @State private var showRecordingSheet = false
    @State private var selectedTab = 0
    @EnvironmentObject var di: ServiceContainer
    
    // Paywall state for recording limits
    @State private var showingRecordingLimitPaywall = false
    @StateObject private var featureManager = FeatureManager.shared

    // MARK: - Recording Start Logic
    
    /// Check recording limits and either show paywall or start recording
    private func handleStartRecording() {
        // Always allow if premium
        if di.subscription.isPremium {
            showRecordingSheet = true
            return
        }
        
        // Check if free user can start recording
        let canRecord = featureManager.canStartRecording()
        
        if canRecord.allowed {
            // User can record - proceed to recording view
            showRecordingSheet = true
        } else {
            // User hit limit - show paywall instead
            showingRecordingLimitPaywall = true
        }
    }
    
    /// Handle expanding existing recording sessions (no limit check needed)
    private func handleExpandRecording() {
        showRecordingSheet = true
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            RecordTab(onStartRecording: handleStartRecording, onExpandRecording: handleExpandRecording)
                .tabItem {
                    Image(systemName: "record.circle")
                    Text("Record")
                }
                .tag(0)
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .tag(2)
        }
        .fullScreenCover(isPresented: $showRecordingSheet) {
            RecordingView(
                onSave: {
                    // Notify RecordListView to reload
                    NotificationCenter.default.post(name: .didSaveRecording, object: nil)
                },
                onNavigateToSettings: {
                    // Switch to Settings tab and navigate to live transcription settings
                    selectedTab = 2
                    // Delay the notification to ensure tab switch happens first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: .navigateToLiveTranscriptionSettings, object: nil)
                    }
                }
            )
        }
        .paywall(isPresented: $showingRecordingLimitPaywall, placementId: AppConfigManager.shared.adaptyPlacementID)
    }
}

struct RecordTab: View {
    let onStartRecording: () -> Void
    let onExpandRecording: () -> Void
    @EnvironmentObject var di: ServiceContainer
    @StateObject private var settings = SettingsService.shared
    
    // Navigation state for transcript viewing
    @State private var navigateToTranscript: Bool = false
    @State private var currentTranscriptSession: Session?
    @State private var currentTranscriptRecording: Recording?
    
    // State tracking for UI updates - force refresh when subscription changes
    @State private var subscriptionUpdateTrigger = false
    
    var body: some View {
        NavigationStack {
            Group {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    // iPad centered layout
                    GeometryReader { geometry in
                        HStack {
                            Spacer()
                            
                            if di.subscription.isPremium && settings.isFolderManagementEnabled {
                                FoldersListView(
                                    onStartRecording: onStartRecording,
                                    onExpandRecording: onExpandRecording,
                                    navigateToTranscript: $navigateToTranscript,
                                    currentTranscriptSession: $currentTranscriptSession,
                                    currentTranscriptRecording: $currentTranscriptRecording
                                )
                                .frame(maxWidth: min(geometry.size.width * 0.85, 1000))
                                .onAppear {
                                    print("📁 HomeView: Showing FoldersListView - isPremium: \(di.subscription.isPremium), folderManagement: \(settings.isFolderManagementEnabled)")
                                }
                            } else {
                                RecordListView(
                                    onStartRecording: onStartRecording,
                                    onExpandRecording: onExpandRecording,
                                    navigateToTranscript: $navigateToTranscript,
                                    currentTranscriptSession: $currentTranscriptSession,
                                    currentTranscriptRecording: $currentTranscriptRecording
                                )
                                .frame(maxWidth: min(geometry.size.width * 0.85, 1000))
                                .onAppear {
                                    print("📝 HomeView: Showing RecordListView - isPremium: \(di.subscription.isPremium), folderManagement: \(settings.isFolderManagementEnabled)")
                                }
                            }
                            
                            Spacer()
                        }
                    }
                } else {
                    // iPhone layout  
                    if di.subscription.isPremium && settings.isFolderManagementEnabled {
                        FoldersListView(
                            onStartRecording: onStartRecording,
                            onExpandRecording: onExpandRecording,
                            navigateToTranscript: $navigateToTranscript,
                            currentTranscriptSession: $currentTranscriptSession,
                            currentTranscriptRecording: $currentTranscriptRecording
                        )
                        .onAppear {
                            print("📁 HomeView (iPhone): Showing FoldersListView - isPremium: \(di.subscription.isPremium), folderManagement: \(settings.isFolderManagementEnabled)")
                        }
                    } else {
                        RecordListView(
                            onStartRecording: onStartRecording,
                            onExpandRecording: onExpandRecording,
                            navigateToTranscript: $navigateToTranscript,
                            currentTranscriptSession: $currentTranscriptSession,
                            currentTranscriptRecording: $currentTranscriptRecording
                        )
                        .onAppear {
                            print("📝 HomeView (iPhone): Showing RecordListView - isPremium: \(di.subscription.isPremium), folderManagement: \(settings.isFolderManagementEnabled)")
                        }
                    }
                }
            }
            .id("recordTab_\(subscriptionUpdateTrigger)")  // Force refresh when subscription changes
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { onStartRecording() }) {
                        Image(systemName: "record.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.accentColor)
                    }
                    .accessibilityLabel("Start Recording")
                }
            }
            .navigationDestination(isPresented: $navigateToTranscript) {
                if let session = currentTranscriptSession, let recording = currentTranscriptRecording {
                    TranscriptResultView(session: session, recording: recording)
                } else {
                    Text("No transcript available")
                        .foregroundColor(.secondary)
                }
            }
            // Listen for subscription status changes to refresh UI immediately
            .onReceive(NotificationCenter.default.publisher(for: .subscriptionStatusChanged)) { notification in
                print("🔄 HomeView: Subscription status changed notification received")
                if let isPremium = notification.userInfo?["isPremium"] as? Bool {
                    print("📱 HomeView: Updating UI for subscription change - isPremium: \(isPremium), folderManagement: \(settings.isFolderManagementEnabled)")
                    
                    // Force UI refresh by toggling state
                    subscriptionUpdateTrigger.toggle()
                    
                    // Small delay to ensure settings are synchronized
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        subscriptionUpdateTrigger.toggle()
                    }
                }
            }
        }
    }
}

struct TranscriptsTab: View {
    var body: some View {
        Text("Transcripts")
            .font(.title)
            .foregroundColor(.secondary)
    }
}

struct SettingsTab: View {
    var body: some View {
        Text("Settings")
            .font(.title)
            .foregroundColor(.secondary)
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
