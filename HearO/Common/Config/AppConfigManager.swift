import Foundation

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
        """
    }
}

