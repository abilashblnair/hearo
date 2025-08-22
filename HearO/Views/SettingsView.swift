import SwiftUI
import MessageUI
import WebKit

struct SettingsView: View {
    @State private var showMail = false
    @State private var mailResult: Result<MFMailComposeResult, Error>? = nil
    @State private var showRating: Bool = false
    @State private var rating: Int = 0
    @State private var showAppStore: Bool = false
    @State private var navigationPath = NavigationPath()

    let appStoreURL = URL(string: "https://apps.apple.com/in/app/auryo/id6751236806")!

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: WebviewType.self) { webviewType in
                WebView(webviewType: webviewType)
                    .navigationTitle(webviewType.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showRating) {
            RatingSheet(rating: $rating, onSubmit: handleRating)
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        Section(header: sectionHeader("General")) {
            settingsRow(
                title: "About Us",
                icon: "info.circle",
                action: { navigationPath.append(WebviewType.aboutUs) }
            )
            settingsRow(
                title: "Terms & Conditions",
                icon: "doc.text",
                action: { navigationPath.append(WebviewType.terms) }
            )
            settingsRow(
                title: "Privacy Policy",
                icon: "hand.raised",
                action: { navigationPath.append(WebviewType.privacy) }
            )
            appVersionRow
        }

        Section(header: sectionHeader("Support")) {
            settingsRow(
                title: "Send Feedback",
                icon: "envelope",
                action: sendFeedback
            )
            settingsRow(
                title: "App Review",
                icon: "star",
                action: openAppStoreFeedback
            )
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

    func openWeb(type: WebviewType) {
        navigationPath.append(type)
    }

    func handleRating(_ value: Int) {
        showRating = false
        if value >= 4 {
            // Redirect to App Store
            UIApplication.shared.open(appStoreURL)
        } else {
            // Show feedback option for ratings less than 4
            sendFeedback()
        }
    }

    func sendFeedback() {
        let email = Constants.feedbackEmail
        if let url = URL(string: "mailto:\(email)") {
            UIApplication.shared.open(url)
        }
    }

    func openAppStoreFeedback() {
        UIApplication.shared.open(appStoreURL)
    }
}

struct RatingSheet: View {
    @Binding var rating: Int
    var onSubmit: (Int) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Rate Us")
                .font(.title)
                .bold()
            HStack {
                ForEach(1...5, id: \ .self) { i in
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
