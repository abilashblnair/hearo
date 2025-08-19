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
    var body: some View {
        NavigationStack {
            Group {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    // iPad centered layout
                    GeometryReader { geometry in
                        HStack {
                            Spacer()
                            
                            RecordListView(showRecordingSheet: $showRecordingSheet)
                                .frame(maxWidth: min(geometry.size.width * 0.85, 1000))
                            
                            Spacer()
                        }
                    }
                } else {
                    // iPhone layout
                    RecordListView(showRecordingSheet: $showRecordingSheet)
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
