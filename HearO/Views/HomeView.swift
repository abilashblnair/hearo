import SwiftUI

struct HomeView: View {
    @State private var showRecordingSheet = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            RecordTab(showRecordingSheet: $showRecordingSheet)
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
            RecordingView(onSave: {
                // Notify RecordListView to reload
                NotificationCenter.default.post(name: .didSaveRecording, object: nil)
            })
        }
    }
}

struct RecordTab: View {
    @Binding var showRecordingSheet: Bool
    @EnvironmentObject var di: ServiceContainer
    @StateObject private var settings = SettingsService.shared
    
    // Navigation state for transcript viewing
    @State private var navigateToTranscript: Bool = false
    @State private var currentTranscriptSession: Session?
    @State private var currentTranscriptRecording: Recording?
    
    var body: some View {
        NavigationStack {
            Group {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    // iPad centered layout
                    GeometryReader { geometry in
                        HStack {
                            Spacer()
                            
                            if settings.isFolderManagementEnabled {
                                FoldersListView(
                                    showRecordingSheet: $showRecordingSheet,
                                    navigateToTranscript: $navigateToTranscript,
                                    currentTranscriptSession: $currentTranscriptSession,
                                    currentTranscriptRecording: $currentTranscriptRecording
                                )
                                .frame(maxWidth: min(geometry.size.width * 0.85, 1000))
                            } else {
                                RecordListView(
                                    showRecordingSheet: $showRecordingSheet,
                                    navigateToTranscript: $navigateToTranscript,
                                    currentTranscriptSession: $currentTranscriptSession,
                                    currentTranscriptRecording: $currentTranscriptRecording
                                )
                                .frame(maxWidth: min(geometry.size.width * 0.85, 1000))
                            }
                            
                            Spacer()
                        }
                    }
                } else {
                    // iPhone layout
                    if settings.isFolderManagementEnabled {
                        FoldersListView(
                            showRecordingSheet: $showRecordingSheet,
                            navigateToTranscript: $navigateToTranscript,
                            currentTranscriptSession: $currentTranscriptSession,
                            currentTranscriptRecording: $currentTranscriptRecording
                        )
                    } else {
                        RecordListView(
                            showRecordingSheet: $showRecordingSheet,
                            navigateToTranscript: $navigateToTranscript,
                            currentTranscriptSession: $currentTranscriptSession,
                            currentTranscriptRecording: $currentTranscriptRecording
                        )
                    }
                }
            }
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showRecordingSheet = true }) {
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
