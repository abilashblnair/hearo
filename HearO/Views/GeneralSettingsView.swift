import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var di: ServiceContainer
    @StateObject private var settings = SettingsService.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    
    // MARK: - Paywall State
    @State private var showPaywall = false

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
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(nil, for: .navigationBar)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .paywall(isPresented: $showPaywall, placementId: AppConfigManager.shared.adaptyPlacementID)
        .fullScreenCover(isPresented: $subscriptionManager.showSubscriptionSuccessView) {
            SubscriptionSuccessView()
                .environmentObject(subscriptionManager)
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        Section(header: sectionHeader("Recording Settings")) {
            folderManagementToggle
            liveTranscriptionToggle
            recordingNotificationsToggle
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
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            Button(action: action) {
                Label(title, systemImage: icon)
            }
        }
    }

    // MARK: - Folder Management
    
    @ViewBuilder
    private var folderManagementToggle: some View {
        HStack {
            if UIDevice.current.userInterfaceIdiom == .pad {
                Image(systemName: "folder.fill")
                    .foregroundColor(.blue)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Folder Management")
                            .fontWeight(.medium)
                        if !di.subscription.isPremium {
                            Text("PREMIUM")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .cornerRadius(4)
                        }
                    }
                    Text("Organize recordings in folders")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: folderManagementBinding)
                    .labelsHidden()
            } else {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Folder Management")
                            if !di.subscription.isPremium {
                                Text("PREMIUM")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange)
                                    .cornerRadius(4)
                            }
                        }
                        Text("Organize recordings in folders")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                Toggle("", isOn: folderManagementBinding)
                    .labelsHidden()
            }
        }
    }
    
    @ViewBuilder
    private var liveTranscriptionToggle: some View {
        HStack {
            if UIDevice.current.userInterfaceIdiom == .pad {
                Image(systemName: "captions.bubble.fill")
                    .foregroundColor(.purple)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Transcription")
                        .fontWeight(.medium)
                    Text("Real-time speech-to-text while recording")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $settings.isLiveTranscriptionEnabled)
                    .labelsHidden()
            } else {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Transcription")
                        Text("Real-time speech-to-text while recording")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "captions.bubble.fill")
                        .foregroundColor(.purple)
                }
                
                Spacer()
                
                Toggle("", isOn: $settings.isLiveTranscriptionEnabled)
                    .labelsHidden()
            }
        }
    }
    
    @ViewBuilder
    private var recordingNotificationsToggle: some View {
        HStack {
            if UIDevice.current.userInterfaceIdiom == .pad {
                Image(systemName: "bell.fill")
                    .foregroundColor(.orange)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recording Notifications")
                        .fontWeight(.medium)
                    Text("Show notifications during recording")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $settings.showRecordingNotifications)
                    .labelsHidden()
            } else {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recording Notifications")
                        Text("Show notifications during recording")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.orange)
                }
                
                Spacer()
                
                Toggle("", isOn: $settings.showRecordingNotifications)
                    .labelsHidden()
            }
        }
    }
    
    
    // MARK: - Computed Properties
    
    private var folderManagementBinding: Binding<Bool> {
        Binding<Bool>(
            get: { 
                // If premium, return actual setting value
                // If not premium, return false (disabled)
                di.subscription.isPremium ? settings.isFolderManagementEnabled : false
            },
            set: { newValue in
                // Check if user can manage folders
                let canManage = di.featureManager.canManageFolders()
                if canManage.allowed {
                    settings.isFolderManagementEnabled = newValue
                } else {
                    // Show paywall for non-premium users
                    showPaywall = true
                }
            }
        )
    }
}