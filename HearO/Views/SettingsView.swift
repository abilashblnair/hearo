import SwiftUI
import WebKit

struct SettingsView: View {
    @EnvironmentObject var di: ServiceContainer
    @StateObject private var settings = SettingsService.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    
    // MARK: - Navigation State
    @State private var navigateToGeneral = false
    
    // MARK: - Paywall State
    @State private var showPaywall = false
    
    // MARK: - Restore State
    @State private var isRestoring = false
    @State private var showRestoreAlert = false
    @State private var restoreMessage = ""
    @State private var restoreSuccess = false

    var body: some View {
        NavigationStack {
            List {
                // Premium status section
                Section(header: Text("Account")) {
                    premiumStatusSection
                    
                    // Restore purchases option
                    if !di.subscription.isPremium {
                        restorePurchasesSection
                    }
                }
                
                
                // Quick toggle for folder management with immediate effect
                Section(header: Text("Quick Settings")) {
                    HStack {
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
                            .disabled(!di.subscription.isPremium && !settings.isFolderManagementEnabled)
                    }
                }
                
                Section(header: Text("Settings Categories")) {
                    NavigationLink(destination: GeneralSettingsView()) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("General")
                                Text("Recording, audio, and app settings")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    
                    // Only show Storage & Files when folder management is enabled
                    if settings.isFolderManagementEnabled {
                        NavigationLink(destination: RecordingManagementView()) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Storage & Files")
                                    Text("Manage recordings and folders")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: "externaldrive.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    
                    NavigationLink(destination: AppInfoView()) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("About & Support")
                                Text("App info, feedback, and legal")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(nil, for: .navigationBar)
            .overlay {
                // Programmatic navigation to General settings
                NavigationLink(destination: GeneralSettingsView(), isActive: $navigateToGeneral) { EmptyView() }
                    .hidden()
            }
        }
        .paywall(isPresented: $showPaywall, placementId: AppConfigManager.shared.adaptyPlacementID)
        .fullScreenCover(isPresented: $subscriptionManager.showSubscriptionSuccessView) {
            SubscriptionSuccessView()
                .environmentObject(subscriptionManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToLiveTranscriptionSettings)) { _ in
            navigateToGeneral = true
        }
        .navigationDestination(isPresented: $navigateToGeneral) {
            GeneralSettingsView()
        }
        .alert("Restore Purchases", isPresented: $showRestoreAlert) {
            Button("OK") { }
        } message: {
            Text(restoreMessage)
        }
    }
    
    // MARK: - Premium Status Section
    
    @ViewBuilder
    private var premiumStatusSection: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(di.subscription.isPremium ? "Premium" : "Free Plan")
                        .fontWeight(di.subscription.isPremium ? .semibold : .regular)
                    
                    if di.subscription.isPremium {
                        if let profile = di.subscription.profile,
                           let accessLevel = profile.accessLevels["premium"],
                           let expiresAt = accessLevel.expiresAt {
                            Text("Expires \(expiresAt, style: .date)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Active subscription")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Upgrade to unlock premium features")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } icon: {
                Image(systemName: di.subscription.isPremium ? "crown.fill" : "crown")
                    .foregroundColor(di.subscription.isPremium ? .orange : .gray)
            }
            
            Spacer()
            
            // Refresh button (always visible for testing/troubleshooting)
            Button(action: {
                Task {
                    await refreshSubscriptionStatus()
                }
            }) {
                Image(systemName: di.subscription.isLoading ? "arrow.clockwise" : "arrow.clockwise.circle")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .rotationEffect(.degrees(di.subscription.isLoading ? 360 : 0))
                    .animation(di.subscription.isLoading ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: di.subscription.isLoading)
            }
            .disabled(di.subscription.isLoading)
            
            if !di.subscription.isPremium {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !di.subscription.isPremium {
                showPaywall = true
            }
        }
    }
    
    // MARK: - Restore Purchases Section
    
    @ViewBuilder
    private var restorePurchasesSection: some View {
        Button(action: {
            Task {
                await restorePurchases()
            }
        }) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Restore Purchases")
                        Text("If you previously purchased premium, tap here to restore your subscription")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundColor(isRestoring ? .gray : .blue)
                }
                
                Spacer()
                
                if isRestoring {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .disabled(isRestoring)
        .buttonStyle(PlainButtonStyle())
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
    
    // MARK: - Private Methods
    
    private func refreshSubscriptionStatus() async {
        print("🔄 Manual subscription status refresh requested")
        await subscriptionManager.forceRefreshSubscriptionStatus()
    }
    
    @MainActor
    private func restorePurchases() async {
        isRestoring = true
        
        let result = await subscriptionManager.restorePurchases()
        
        switch result {
        case .success(let profile):
            if profile.accessLevels["premium"]?.isActive == true {
                restoreMessage = "✅ Great! Your premium subscription has been successfully restored."
                restoreSuccess = true
                
                // Automatically enable folder management for restored premium users
                print("📁 SettingsView: Enabling folder management for restored premium user")
                settings.isFolderManagementEnabled = true
                
                // Show success feedback
                await subscriptionManager.forceRefreshSubscriptionStatus()
                
                // Add haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                
            } else {
                restoreMessage = "No active premium subscription was found to restore. If you believe this is an error, please contact support."
                restoreSuccess = false
                
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
            }
            
        case .failure(let error):
            print("❌ SettingsView: Restore failed: \(error)")
            restoreMessage = "Failed to restore purchases: \(error.localizedDescription)\n\nPlease try again or contact support if the problem persists."
            restoreSuccess = false
            
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
        
        isRestoring = false
        showRestoreAlert = true
    }
}

// MARK: - Recording Management View
struct RecordingManagementView: View {
    @EnvironmentObject var di: ServiceContainer
    @Environment(\.modelContext) private var modelContext
    @StateObject private var settings = SettingsService.shared
    @StateObject private var storageManager = StorageManager.shared
    
    // MARK: - Storage State
    @State private var storageStats: StorageStats?
    @State private var showingClearDataAlert = false
    @State private var showingSecondaryConfirmation = false
    @State private var confirmationText = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false
    
    var body: some View {
        List {
            // Enhanced Storage Information Section
            Section(header: Text("Storage Information")) {
                if let stats = storageStats {
                    VStack(spacing: 8) {
                        HStack {
                            Label("Total Recordings", systemImage: "waveform")
                            Spacer()
                            Text("\(stats.totalRecordings)")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Label("Storage Used", systemImage: "externaldrive")
                            Spacer()
                            Text(stats.formattedFileSize)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Label("Total Duration", systemImage: "clock")
                            Spacer()
                            Text(stats.formattedDuration)
                                .foregroundColor(.secondary)
                        }
                        
                        if settings.isFolderManagementEnabled {
                            HStack {
                                Label("Folders", systemImage: "folder")
                                Spacer()
                                Text("\(stats.totalFolders)")
                                    .foregroundColor(.secondary)
                            }
                            
                            if stats.emptyFolders > 0 {
                                HStack {
                                    Label("Empty Folders", systemImage: "folder.badge.minus")
                                    Spacer()
                                    Text("\(stats.emptyFolders)")
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                } else {
                    HStack {
                        Label("Loading...", systemImage: "externaldrive")
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                
                // Refresh button
                Button(action: loadStorageStats) {
                    Label("Refresh Statistics", systemImage: "arrow.clockwise")
                }
                .disabled(storageManager.isProcessing)
            }
            
            // Folder Actions Section
            if settings.isFolderManagementEnabled {
                Section(header: Text("Folder Management")) {
                    Button(action: cleanEmptyFolders) {
                        HStack {
                            Label("Clean Empty Folders", systemImage: "folder.badge.minus")
                                .foregroundColor(storageManager.isProcessing ? .gray : .orange)
                            
                            if storageManager.isProcessing && storageManager.operationStatus.contains("folder") {
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(storageManager.isProcessing)
                    
                    if let stats = storageStats, stats.emptyFolders > 0 {
                        Text("\(stats.emptyFolders) empty folder\(stats.emptyFolders == 1 ? "" : "s") can be cleaned")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Data Management Section
            Section(header: Text("Data Management")) {
                Button(action: showClearDataConfirmation) {
                    HStack {
                        Label("Clear All Data", systemImage: "trash.fill")
                            .foregroundColor(storageManager.isProcessing ? .gray : .red)
                        
                        if storageManager.isProcessing && storageManager.operationStatus.contains("clear") {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(storageManager.isProcessing)
                
                if let stats = storageStats {
                    Text("⚠️ Will permanently delete \(stats.totalRecordings) recordings (\(stats.formattedFileSize))")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Storage & Files")
        .refreshable {
            loadStorageStats()
        }
        .task {
            loadStorageStats()
        }
        .alert("Storage Operation", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .alert("⚠️ Clear All Data", isPresented: $showingClearDataAlert) {
            Button("Cancel", role: .cancel) { 
                // Do nothing - user cancelled
            }
            Button("Continue", role: .destructive) {
                // Show secondary confirmation sheet
                showingSecondaryConfirmation = true
                confirmationText = ""
            }
        } message: {
            if let stats = storageStats {
                Text("This will permanently delete:\n\n• \(stats.totalRecordings) recordings\n• \(stats.totalFolders - 1) custom folders\n• All transcripts and summaries\n• \(stats.formattedFileSize) of audio data\n\nThis action cannot be undone!")
            } else {
                Text("This will permanently delete all your recordings, transcripts, summaries, and audio files.\n\nThis action cannot be undone!")
            }
        }
        .sheet(isPresented: $showingSecondaryConfirmation) {
            ClearDataConfirmationView(
                confirmationText: $confirmationText,
                onConfirm: {
                    clearAllData()
                    showingSecondaryConfirmation = false
                    confirmationText = ""
                },
                onCancel: {
                    showingSecondaryConfirmation = false
                    confirmationText = ""
                },
                storageStats: storageStats
            )
        }
    }
    
    // MARK: - Storage Actions
    
    private func loadStorageStats() {
        Task {
            do {
                storageStats = try await storageManager.getStorageStats()
            } catch {
                alertMessage = "Failed to load storage stats: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
    
    private func cleanEmptyFolders() {
        Task {
            do {
                let result = try await storageManager.cleanEmptyFolders()
                alertMessage = result.message
                showingAlert = true
                // Refresh stats after cleanup
                loadStorageStats()
            } catch {
                alertMessage = "Failed to clean folders: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
    
    private func showClearDataConfirmation() {
        showingClearDataAlert = true
    }
    
    private func clearAllData() {
        Task {
            do {
                let result = try await storageManager.clearAllData()
                alertMessage = result.message
                showingAlert = true
                // Refresh stats after clearing
                loadStorageStats()
            } catch {
                alertMessage = "Failed to clear data: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
}

// MARK: - App Info View
struct AppInfoView: View {
    let appStoreURL = URL(string: "https://apps.apple.com/in/app/auryo/id6751236806")!
    
    var body: some View {
        List {
            Section(header: Text("App Information")) {
                HStack {
                    Label("Version", systemImage: "app.badge")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("Legal")) {
                NavigationLink(destination: WebView(webviewType: .aboutUs)) {
                    Label("About Us", systemImage: "info.circle")
                }
                
                NavigationLink(destination: WebView(webviewType: .terms)) {
                    Label("Terms & Conditions", systemImage: "doc.text")
                }
                
                NavigationLink(destination: WebView(webviewType: .privacy)) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
            }
            
            Section(header: Text("Support")) {
                Button(action: sendFeedback) {
                    Label("Send Feedback", systemImage: "envelope")
                        .foregroundColor(.blue)
                }
                
                Button(action: { UIApplication.shared.open(appStoreURL) }) {
                    Label("Rate App", systemImage: "star")
                        .foregroundColor(.blue)
                }
            }
        }
        .navigationTitle("About & Support")
    }
    
    private func sendFeedback() {
        let email = Constants.feedbackEmail
        if let url = URL(string: "mailto:\(email)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Shared Components

struct WebView: UIViewRepresentable {
    let webviewType: WebviewType

    func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if let url = URL(string: webviewType.url) {
            webView.load(URLRequest(url: url))
        }
    }
}

enum Constants {
    static let feedbackEmail = "aarya.ai.info@gmail.com"
}

enum WebviewType: Hashable {
    case aboutUs, terms, privacy
    
    var url: String {
        switch self {
        case .aboutUs:
            return "https://auryo-e3f8f.web.app"
        case .terms:
            return "https://auryo-e3f8f.web.app/terms"
        case .privacy:
            return "https://auryo-e3f8f.web.app/privacy"
        }
    }

    var title: String {
        switch self {
        case .aboutUs:
            return "About Us"
        case .terms:
            return "Terms"
        case .privacy:
            return "Privacy"
        }
    }
}