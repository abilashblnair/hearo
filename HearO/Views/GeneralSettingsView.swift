import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var di: ServiceContainer
    @StateObject private var settings = SettingsService.shared
    

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    // iPad centered layout
                    GeometryReader { geometry in
                        HStack {
                            Spacer()

                            ScrollView {
                                VStack(spacing: 24) {
                                    settingsContent
                                }
                                .padding(.horizontal, 40)
                                .padding(.vertical, 20)
                            }
                            .frame(maxWidth: min(geometry.size.width * 0.8, 800))

                            Spacer()
                        }
                    }
                } else {
                    // iPhone layout
                    List {
                        settingsContent
                    }
                }
            }
            .navigationTitle("General")
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    @ViewBuilder
    private var settingsContent: some View {
        Section(header: sectionHeader("Recording Settings")) {
            folderManagementToggle
            liveTranscriptionToggle
            recordingNotificationsToggle
            audioQualityPicker
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.top, 16)
        } else {
            Text(title)
        }
    }

    @ViewBuilder
    private func settingsRow(title: String, icon: String, action: @escaping () -> Void) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            Button(action: action) {
                HStack(spacing: 16) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 30)

                    Text(title)
                        .font(.body)
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                )
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            Button(action: action) {
                Label(title, systemImage: icon)
                    .foregroundColor(.primary)
            }
        }
    }

    @ViewBuilder
    private var appVersionRow: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            HStack(spacing: 16) {
                Image(systemName: "app.badge")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 30)

                Text("App Version")
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
        } else {
            HStack {
                Label("App Version", systemImage: "app.badge")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Recording Settings Views
    
    @ViewBuilder
    private var folderManagementToggle: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            HStack(spacing: 16) {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Folder Management")
                        .font(.body)
                        .foregroundColor(.primary)
                    Text("Organize recordings in folders")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: $settings.isFolderManagementEnabled)
                    .labelsHidden()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
        } else {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Folder Management")
                        Text("Organize recordings in folders")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                Toggle("", isOn: $settings.isFolderManagementEnabled)
                    .labelsHidden()
            }
        }
    }
    
    @ViewBuilder
    private var liveTranscriptionToggle: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            HStack(spacing: 16) {
                Image(systemName: "text.bubble")
                    .font(.title2)
                    .foregroundColor(.green)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Transcription")
                        .font(.body)
                        .foregroundColor(.primary)
                    Text("Real-time speech-to-text during recording")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: $settings.isLiveTranscriptionEnabled)
                    .labelsHidden()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
        } else {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Transcription")
                        Text("Real-time speech-to-text during recording")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "text.bubble")
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                Toggle("", isOn: $settings.isLiveTranscriptionEnabled)
                    .labelsHidden()
            }
        }
    }
    
    @ViewBuilder
    private var recordingNotificationsToggle: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            HStack(spacing: 16) {
                Image(systemName: "bell")
                    .font(.title2)
                    .foregroundColor(.orange)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Recording Notifications")
                        .font(.body)
                        .foregroundColor(.primary)
                    Text("Show alerts when recording starts/stops")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: $settings.showRecordingNotifications)
                    .labelsHidden()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
        } else {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recording Notifications")
                        Text("Show alerts when recording starts/stops")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "bell")
                        .foregroundColor(.orange)
                }
                
                Spacer()
                
                Toggle("", isOn: $settings.showRecordingNotifications)
                    .labelsHidden()
            }
        }
    }
    
    @ViewBuilder
    private var audioQualityPicker: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            HStack(spacing: 16) {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundColor(.purple)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Audio Quality")
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(settings.audioQuality.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Menu(settings.audioQuality.displayName) {
                    ForEach(AudioQuality.allCases) { quality in
                        Button(quality.displayName) {
                            settings.audioQuality = quality
                        }
                    }
                }
                .foregroundColor(.blue)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
        } else {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio Quality")
                        Text(settings.audioQuality.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "waveform")
                        .foregroundColor(.purple)
                }
                
                Spacer()
                
                Menu(settings.audioQuality.displayName) {
                    ForEach(AudioQuality.allCases) { quality in
                        Button(quality.displayName) {
                            settings.audioQuality = quality
                        }
                    }
                }
                .foregroundColor(.blue)
            }
        }
    }

}


