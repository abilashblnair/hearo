import Foundation
import Combine

/// Manages feature access and limitations for free vs premium users
@MainActor
final class FeatureManager: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = FeatureManager()
    
    // MARK: - Published Properties
    
    /// Current daily recording count
    @Published private(set) var dailyRecordingCount: Int = 0
    
    /// Additional recordings earned from ads
    @Published private(set) var bonusRecordings: Int = 0
    
    /// Last reset date for daily counters
    @Published private(set) var lastResetDate: Date?
    
    // MARK: - Dependencies
    
    private let subscriptionService = SubscriptionService.shared
    private let userDefaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Constants
    
    /// Free tier limitations
    enum FreeTierLimits {
        static let maxRecordingDuration: TimeInterval = 5 * 60 // 5 minutes
        static let dailyRecordingLimit = 2
        static let maxBonusRecordings = 2
        static let rewardedAdsPerBonus = 2 // 2 ads = +1 recording
        static let historyRetentionDays = 7
        static let allowedLanguages: Set<String> = ["en", "es", "fr"] // English, Spanish, French
    }
    
    // MARK: - UserDefaults Keys
    
    private enum CacheKeys {
        static let dailyRecordingCount = "feature_daily_recording_count"
        static let bonusRecordings = "feature_bonus_recordings"
        static let lastResetDate = "feature_last_reset_date"
        static let rewardedAdsWatched = "feature_rewarded_ads_watched"
        static let recordingHistory = "feature_recording_history"
    }
    
    // MARK: - Initialization
    
    private init() {
        loadCachedData()
        setupDailyReset()
        startMonitoringSubscription()
    }
    
    // MARK: - Recording Limits
    
    /// Check if user can start a new recording
    func canStartRecording() -> (allowed: Bool, reason: String?) {
        if subscriptionService.isPremium {
            return (true, nil)
        }
        
        let totalAllowedToday = FreeTierLimits.dailyRecordingLimit + bonusRecordings
        
        if dailyRecordingCount >= totalAllowedToday {
            return (false, "Daily recording limit reached. Watch ads for more recordings or upgrade to Premium.")
        }
        
        return (true, nil)
    }
    
    /// Check if current recording duration exceeds free tier limit
    func isRecordingDurationExceeded(_ duration: TimeInterval) -> Bool {
        if subscriptionService.isPremium {
            return false
        }
        return duration >= FreeTierLimits.maxRecordingDuration
    }
    
    /// Get maximum allowed recording duration
    func getMaxRecordingDuration() -> TimeInterval? {
        return subscriptionService.isPremium ? nil : FreeTierLimits.maxRecordingDuration
    }
    
    /// Record that a new recording has been started
    func recordNewRecording() {
        if !subscriptionService.isPremium {
            dailyRecordingCount += 1
            saveDailyCount()
        }
    }
    
    /// Get remaining recordings for today
    func getRemainingRecordings() -> Int {
        if subscriptionService.isPremium {
            return -1 // Unlimited
        }
        
        let totalAllowed = FreeTierLimits.dailyRecordingLimit + bonusRecordings
        return max(0, totalAllowed - dailyRecordingCount)
    }
    
    // MARK: - Language Access
    
    /// Check if user has access to a specific language
    func hasAccessToLanguage(_ languageCode: String) -> Bool {
        if subscriptionService.isPremium {
            return true
        }
        return FreeTierLimits.allowedLanguages.contains(languageCode.lowercased())
    }
    
    /// Get list of available languages for current user
    func getAvailableLanguages() -> Set<String> {
        if subscriptionService.isPremium {
            return Set(getSupportedLanguages())
        }
        return FreeTierLimits.allowedLanguages
    }
    
    // MARK: - Export Features
    
    /// Check if user can export recordings
    func canExport() -> (allowed: Bool, reason: String?) {
        if subscriptionService.isPremium {
            return (true, nil)
        }
        return (false, "Export is only available for Premium users. Upgrade to access this feature.")
    }
    
    // MARK: - Folder Management
    
    /// Check if user can create/manage folders
    func canManageFolders() -> (allowed: Bool, reason: String?) {
        if subscriptionService.isPremium {
            return (true, nil)
        }
        return (false, "Folder management is only available for Premium users.")
    }
    
    // MARK: - History Retention
    
    /// Check if a recording should be retained based on age
    func shouldRetainRecording(date: Date) -> Bool {
        if subscriptionService.isPremium {
            return true // Unlimited retention
        }
        
        let daysSinceRecording = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        return daysSinceRecording <= FreeTierLimits.historyRetentionDays
    }
    
    /// Get recordings that should be deleted due to retention policy
    func getRecordingsToDelete(from recordings: [Date]) -> [Date] {
        if subscriptionService.isPremium {
            return []
        }
        
        return recordings.filter { !shouldRetainRecording(date: $0) }
    }
    
    // MARK: - Ad Rewards
    
    /// Check if user can earn bonus recordings from ads
    func canEarnBonusRecordings() -> Bool {
        return !subscriptionService.isPremium && bonusRecordings < FreeTierLimits.maxBonusRecordings
    }
    
    /// Record that user watched a rewarded ad
    func recordRewardedAdWatched() {
        guard !subscriptionService.isPremium else { return }
        
        let adsWatched = userDefaults.integer(forKey: CacheKeys.rewardedAdsWatched) + 1
        userDefaults.set(adsWatched, forKey: CacheKeys.rewardedAdsWatched)
        
        // Check if user earned a bonus recording
        if adsWatched % FreeTierLimits.rewardedAdsPerBonus == 0 && bonusRecordings < FreeTierLimits.maxBonusRecordings {
            bonusRecordings += 1
            saveBonusRecordings()
        }
    }
    
    /// Get progress towards next bonus recording
    func getAdProgressToNextBonus() -> (watched: Int, needed: Int) {
        let adsWatched = userDefaults.integer(forKey: CacheKeys.rewardedAdsWatched)
        let watchedForCurrentBonus = adsWatched % FreeTierLimits.rewardedAdsPerBonus
        return (watched: watchedForCurrentBonus, needed: FreeTierLimits.rewardedAdsPerBonus)
    }
    
    // MARK: - Ads Display
    
    /// Check if ads should be shown
    func shouldShowAds() -> Bool {
        return !subscriptionService.isPremium
    }
    
    // MARK: - Premium Feature Prompts
    
    /// Get premium upgrade prompt message for a specific feature
    func getPremiumPromptMessage(for feature: PremiumFeature) -> String {
        switch feature {
        case .unlimitedRecordings:
            return "Upgrade to Premium for unlimited recordings per day!"
        case .unlimitedDuration:
            return "Upgrade to Premium to record without time limits!"
        case .allLanguages:
            return "Upgrade to Premium to access all translation languages!"
        case .export:
            return "Upgrade to Premium to export your recordings as text or PDF!"
        case .folderManagement:
            return "Upgrade to Premium to organize your recordings in folders!"
        case .unlimitedHistory:
            return "Upgrade to Premium for unlimited recording history!"
        case .noAds:
            return "Upgrade to Premium for an ad-free experience!"
        case .earlyAccess:
            return "Upgrade to Premium to get early access to new features!"
        }
    }
    
    // MARK: - Private Methods
    
    private func loadCachedData() {
        dailyRecordingCount = userDefaults.integer(forKey: CacheKeys.dailyRecordingCount)
        bonusRecordings = userDefaults.integer(forKey: CacheKeys.bonusRecordings)
        lastResetDate = userDefaults.object(forKey: CacheKeys.lastResetDate) as? Date
        
        // Reset daily counters if needed
        resetDailyCountersIfNeeded()
    }
    
    private func saveDailyCount() {
        userDefaults.set(dailyRecordingCount, forKey: CacheKeys.dailyRecordingCount)
    }
    
    private func saveBonusRecordings() {
        userDefaults.set(bonusRecordings, forKey: CacheKeys.bonusRecordings)
    }
    
    private func resetDailyCountersIfNeeded() {
        let calendar = Calendar.current
        let today = Date()
        
        if let lastReset = lastResetDate {
            if !calendar.isDate(lastReset, inSameDayAs: today) {
                resetDailyCounters()
            }
        } else {
            resetDailyCounters()
        }
    }
    
    private func resetDailyCounters() {
        dailyRecordingCount = 0
        bonusRecordings = 0
        lastResetDate = Date()
        
        userDefaults.set(dailyRecordingCount, forKey: CacheKeys.dailyRecordingCount)
        userDefaults.set(bonusRecordings, forKey: CacheKeys.bonusRecordings)
        userDefaults.set(lastResetDate, forKey: CacheKeys.lastResetDate)
        userDefaults.set(0, forKey: CacheKeys.rewardedAdsWatched)
    }
    
    private func setupDailyReset() {
        // Set up timer to check for daily reset at midnight
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let midnight = calendar.startOfDay(for: tomorrow)
        
        let timer = Timer(fire: midnight, interval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resetDailyCounters()
            }
        }
        
        RunLoop.main.add(timer, forMode: .common)
    }
    
    private func startMonitoringSubscription() {
        subscriptionService.$isPremium
            .removeDuplicates()
            .sink { [weak self] isPremium in
                // When user upgrades to premium, reset any temporary restrictions
                if isPremium {
                    self?.handlePremiumUpgrade()
                }
            }
            .store(in: &cancellables)
    }
    
    private func handlePremiumUpgrade() {
        // Premium users get unlimited access, so we can clean up any temporary restrictions
        // This method can be used to handle any special logic when user upgrades
    }
    
    private func getSupportedLanguages() -> [String] {
        // This should return all supported languages in your app
        // For now, returning a comprehensive list
        return ["en", "es", "fr", "de", "it", "pt", "ru", "zh", "ja", "ko", "ar", "hi", "tr", "pl", "nl", "sv", "da", "no", "fi"]
    }
}

// MARK: - Supporting Types

enum PremiumFeature: CaseIterable {
    case unlimitedRecordings
    case unlimitedDuration
    case allLanguages
    case export
    case folderManagement
    case unlimitedHistory
    case noAds
    case earlyAccess
    
    var displayName: String {
        switch self {
        case .unlimitedRecordings:
            return "Unlimited Recordings"
        case .unlimitedDuration:
            return "Unlimited Duration"
        case .allLanguages:
            return "All Languages"
        case .export:
            return "Export Features"
        case .folderManagement:
            return "Folder Management"
        case .unlimitedHistory:
            return "Unlimited History"
        case .noAds:
            return "Ad-Free Experience"
        case .earlyAccess:
            return "Early Access Features"
        }
    }
}
