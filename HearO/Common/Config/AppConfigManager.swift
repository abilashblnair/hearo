import Foundation
import UIKit

/// Centralized configuration manager for the app
@MainActor
final class AppConfigManager: ObservableObject {

    // MARK: - Shared Instance
    static let shared = AppConfigManager()

    // MARK: - Adapty Configuration

    /// Adapty placement ID for premium paywall
    let adaptyPlacementID = "auryo.placement41126"

    // MARK: - App Configuration

    /// App version information
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// Build number
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// Bundle identifier
    var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.aaryea.HearO"
    }

    /// App Store URL for rating and reviews
    var appStoreURL: String {
        return "https://apps.apple.com/app/id\(appStoreID)"
    }

    /// App Store ID for the app (replace with actual App Store ID when available)
    private let appStoreID = "6751236806" // This is a placeholder - replace with your actual App Store ID

    // MARK: - Feature Flags

    /// Whether to use AdaptyUI instead of custom paywall
    let useAdaptyUI = true

    /// Whether to enable debug logging
    var debugLogging: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: - Initialization

    private init() {
        // Private initializer for singleton
    }

    // MARK: - Public Methods

    /// Get configuration summary for debugging
    func getConfigSummary() -> String {
        return """
        App Configuration:
        - Version: \(appVersion) (\(buildNumber))
        - Bundle: \(bundleIdentifier)
        - Adapty Placement: \(adaptyPlacementID)
        - AdaptyUI Enabled: \(useAdaptyUI)
        - Debug Logging: \(debugLogging)
        - App Store URL: \(appStoreURL)
        """
    }

    /// Open App Store for rating
    func openAppStoreForRating() {
        if !appStoreURL.isEmpty {
            // Add the review action parameter to direct users to the review section
            let reviewURL = appStoreURL + "?action=write-review"
            if let url = URL(string: reviewURL) {
                UIApplication.shared.open(url) { success in
                    if !success {
                        print("❌ Failed to open App Store for rating")
                        // Fallback to regular App Store page
                        if let fallbackURL = URL(string: self.appStoreURL) {
                            UIApplication.shared.open(fallbackURL)
                        }
                    }
                }
            }
        } else {
            print("❌ No App Store URL configured")
        }
    }
}
