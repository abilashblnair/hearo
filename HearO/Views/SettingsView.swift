import SwiftUI
import WebKit

struct SettingsView: View {
    @EnvironmentObject var di: ServiceContainer
    @StateObject private var settings = SettingsService.shared

    var body: some View {
        NavigationView {
            List {
                // Quick toggle for folder management with immediate effect
                Section(header: Text("Quick Settings")) {
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
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// MARK: - Recording Management View
struct RecordingManagementView: View {
    @EnvironmentObject var di: ServiceContainer
    @Environment(\.modelContext) private var modelContext
    @StateObject private var settings = SettingsService.shared
    
    @State private var folders: [RecordingFolder] = []
    @State private var allRecordings: [Recording] = []
    @State private var storageUsed: String = "Calculating..."
    
    var body: some View {
        List {
            Section(header: Text("Storage Information")) {
                HStack {
                    Label("Storage Used", systemImage: "externaldrive")
                    Spacer()
                    Text(storageUsed)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Label("Total Recordings", systemImage: "waveform")
                    Spacer()
                    Text("\(allRecordings.count)")
                        .foregroundColor(.secondary)
                }
                
                if settings.isFolderManagementEnabled {
                    HStack {
                        Label("Folders", systemImage: "folder")
                        Spacer()
                        Text("\(folders.count)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if settings.isFolderManagementEnabled {
                Section(header: Text("Folder Actions")) {
                    Button(action: cleanupEmptyFolders) {
                        Label("Clean Empty Folders", systemImage: "trash")
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Section(header: Text("Data Management")) {
                Button(action: exportAllData) {
                    Label("Export All Data", systemImage: "square.and.arrow.up")
                        .foregroundColor(.blue)
                }
                
                Button(action: clearAllData) {
                    Label("Clear All Data", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Storage & Files")
        .onAppear {
            loadData()
            calculateStorageUsed()
        }
    }
    
    private func loadData() {
        let folderStore = FolderDataStore(context: modelContext)
        do {
            folders = try folderStore.fetchFolders()
            allRecordings = try folderStore.fetchAllRecordings()
        } catch {
        }
    }
    
    private func calculateStorageUsed() {
        DispatchQueue.global(qos: .utility).async {
            var totalSize: Int64 = 0
            let fileManager = FileManager.default
            
            for recording in allRecordings {
                let url = recording.finalAudioURL()
                if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                   let size = attributes[.size] as? Int64 {
                    totalSize += size
                }
            }
            
            DispatchQueue.main.async {
                storageUsed = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
            }
        }
    }
    
    private func cleanupEmptyFolders() {
        let folderStore = FolderDataStore(context: modelContext)
        do {
            let emptyFolders = folders.filter { $0.recordings.isEmpty && !$0.isDefault }
            for folder in emptyFolders {
                try folderStore.deleteFolder(folder)
            }
            loadData()
        } catch {
        }
    }
    
    private func exportAllData() {
        // Implementation for data export
    }
    
    private func clearAllData() {
        // Implementation with confirmation dialog
    }
}

// MARK: - App Info View
struct AppInfoView: View {
    @State private var showRating: Bool = false
    @State private var rating: Int = 0
    
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
                
                HStack {
                    Label("Build", systemImage: "hammer")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-")
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
                
                Button(action: { showRating = true }) {
                    Label("Rate App", systemImage: "star")
                        .foregroundColor(.blue)
                }
            }
        }
        .navigationTitle("About & Support")
        .sheet(isPresented: $showRating) {
            RatingSheet(rating: $rating, onSubmit: handleRating)
        }
    }
    
    private func sendFeedback() {
        let email = Constants.feedbackEmail
        if let url = URL(string: "mailto:\(email)") {
            UIApplication.shared.open(url)
        }
    }
    
    private func handleRating(_ value: Int) {
        showRating = false
        if value >= 4 {
            UIApplication.shared.open(appStoreURL)
        } else {
            sendFeedback()
        }
    }
}

// MARK: - Shared Components

struct RatingSheet: View {
    @Binding var rating: Int
    var onSubmit: (Int) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Rate Us")
                .font(.title)
                .bold()
            HStack {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .resizable()
                        .frame(width: 40, height: 40)
                        .foregroundColor(.yellow)
                        .onTapGesture {
                            rating = i
                        }
                }
            }
            Button("Submit") {
                onSubmit(rating)
            }
            .padding()
        }
        .padding()
    }
}

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