import Foundation
import Combine
import Adapty
import StoreKit

/// Service responsible for managing subscription status and Adapty integration
@MainActor
final class SubscriptionService: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = SubscriptionService()
    
    // MARK: - Published Properties
    
    /// Current subscription status
    @Published private(set) var isPremium: Bool = false
    
    /// Whether subscription status is currently being loaded
    @Published private(set) var isLoading: Bool = true
    
    /// Current subscription profile
    @Published private(set) var profile: AdaptyProfile?
    
    /// Available paywall for premium upgrade
    @Published private(set) var paywall: AdaptyPaywall?
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let userDefaults = UserDefaults.standard
    
    // UserDefaults keys for caching
    private enum CacheKeys {
        static let isPremium = "subscription_is_premium"
        static let lastProfileUpdate = "subscription_last_profile_update"
        static let hasAttemptedRestore = "subscription_has_attempted_restore"
        static let isFirstLaunch = "subscription_is_first_launch"
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load cached subscription status
        loadCachedStatus()
        
        // Start monitoring subscription status
        startMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Fetch the current subscription profile from Adapty
    func fetchProfile() async {
        // Only show loading if we don't have cached data
        let shouldShowLoading = profile == nil
        
        if shouldShowLoading {
            await MainActor.run {
                self.isLoading = true
            }
        }
        
        do {
            let fetchedProfile = try await Adapty.getProfile()
            await MainActor.run {
                self.profile = fetchedProfile
                self.updatePremiumStatus(from: fetchedProfile)
                self.isLoading = false
                self.cacheStatus()
            }
            
            print("✅ Successfully fetched subscription profile: isPremium=\(isPremium)")
            
        } catch {
            print("❌ Failed to fetch Adapty profile: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    /// Force fetch profile (always shows loading)
    func forceFetchProfile() async {
        await MainActor.run {
            self.isLoading = true
        }
        await fetchProfile()
    }
    
    /// Load the premium paywall
    func loadPaywall() async {
        do {
            let loadedPaywall = try await Adapty.getPaywall(placementId: "premium_upgrade")
            await MainActor.run {
                self.paywall = loadedPaywall
            }
        } catch {
            print("Failed to load paywall: \(error)")
        }
    }
    
    /// Make a purchase using the provided paywall product
    func makePurchase(product: AdaptyPaywallProduct) async -> Result<AdaptyPurchaseResult, Error> {
        do {
            let result = try await Adapty.makePurchase(product: product)
            
            // Update profile after successful purchase
            await fetchProfile()
            
            return .success(result)
        } catch {
            return .failure(error)
        }
    }
    
    /// Restore previous purchases
    func restorePurchases() async -> Result<AdaptyProfile, Error> {
        do {
            print("🔄 Attempting to restore purchases...")
            let restoredProfile = try await Adapty.restorePurchases()
            
            await MainActor.run {
                self.profile = restoredProfile
                self.updatePremiumStatus(from: restoredProfile)
                self.cacheStatus()
            }
            
            let hasPremium = restoredProfile.accessLevels["premium"]?.isActive == true
            print("✅ Restore completed: isPremium=\(hasPremium)")
            
            return .success(restoredProfile)
        } catch {
            print("❌ Restore failed: \(error)")
            return .failure(error)
        }
    }
    
    /// Set user identifier for analytics and customer support
    func identifyUser(with customerUserId: String) async {
        do {
            try await Adapty.identify(customerUserId)
        } catch {
            print("Failed to identify user: \(error)")
        }
    }
    
    /// Reset fresh install detection (for testing purposes)
    func resetFreshInstallDetection() {
        print("🧪 Resetting fresh install detection flags...")
        userDefaults.removeObject(forKey: CacheKeys.hasAttemptedRestore)
        userDefaults.removeObject(forKey: CacheKeys.isFirstLaunch)
        userDefaults.removeObject(forKey: CacheKeys.isPremium)
        userDefaults.removeObject(forKey: CacheKeys.lastProfileUpdate)
        userDefaults.removeObject(forKey: "subscription_last_restore_attempt") // Clear restore attempt tracking
        print("✅ Fresh install flags reset - next launch will trigger automatic restore")
    }
    
    /// Debug method to explain sandbox subscription duplicates
    func logSandboxSubscriptionInfo() {
        print("""
        📝 SANDBOX SUBSCRIPTION INFO:
        • Sandbox environment creates duplicate subscription entries during testing
        • Each test purchase/restore creates new subscription records
        • Sandbox subscriptions have accelerated renewal cycles (minutes vs months)
        • Multiple app launches during development can trigger restoration
        
        🧹 TO CLEAN UP DUPLICATES:
        1. Go to iOS Settings > Apple ID > Subscriptions
        2. Cancel duplicate test subscriptions
        3. Or use a fresh sandbox test account
        4. For production, duplicates won't occur with real user behavior
        """)
    }
    
    // MARK: - Private Methods
    
    private func loadCachedStatus() {
        let cachedPremium = userDefaults.bool(forKey: CacheKeys.isPremium)
        let lastUpdate = userDefaults.object(forKey: CacheKeys.lastProfileUpdate) as? Date
        
        // Use cached status and determine if we need to show loading state
        isPremium = cachedPremium
        
        // Only show loading if we have no cached data or it's very old (>7 days)
        let shouldShowLoading: Bool
        if let lastUpdate = lastUpdate {
            let daysSinceUpdate = Date().timeIntervalSince(lastUpdate) / (24 * 60 * 60)
            shouldShowLoading = daysSinceUpdate > 7
        } else {
            shouldShowLoading = true // No cache at all
        }
        
        isLoading = shouldShowLoading
        
        print("📱 Loaded cached subscription status: isPremium=\(cachedPremium), showLoading=\(shouldShowLoading)")
    }
    
    private func cacheStatus() {
        userDefaults.set(isPremium, forKey: CacheKeys.isPremium)
        userDefaults.set(Date(), forKey: CacheKeys.lastProfileUpdate)
    }
    
    private func updatePremiumStatus(from profile: AdaptyProfile) {
        // Check if user has active premium subscription
        let hasPremiumAccess = profile.accessLevels["premium"]?.isActive == true
        
        if isPremium != hasPremiumAccess {
            let wasFreePreviously = !isPremium
            isPremium = hasPremiumAccess
            
            // Automatically enable folder management when user becomes premium
            if hasPremiumAccess && wasFreePreviously {
                print("📁 SubscriptionService: User became premium - enabling folder management")
                SettingsService.shared.isFolderManagementEnabled = true
            }
            
            // Post notification for other parts of the app to react
            NotificationCenter.default.post(
                name: .subscriptionStatusChanged,
                object: nil,
                userInfo: ["isPremium": hasPremiumAccess]
            )
        }
    }
    
    private func startMonitoring() {
        // Initial profile fetch - always fetch fresh data on app launch
        // but don't show loading if we have recent cached data
        Task {
            await fetchProfile()
            await loadPaywall()
        }
        
        // Set up periodic profile refresh (every 24 hours)
        Timer.publish(every: 24 * 60 * 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.fetchProfile()
                }
            }
            .store(in: &cancellables)
    }
    
    /// Force refresh on app launch - always fetches fresh data and handles fresh installs
    func refreshOnAppLaunch() async {
        print("🚀 Refreshing subscription status on app launch...")
        
        // Check if this is a fresh install or first launch after reinstall
        let hasAttemptedRestore = userDefaults.bool(forKey: CacheKeys.hasAttemptedRestore)
        let isFirstLaunch = !userDefaults.bool(forKey: CacheKeys.isFirstLaunch)
        
        if isFirstLaunch || !hasAttemptedRestore {
            print("🆕 Fresh install detected - attempting automatic purchase restoration...")
            await automaticRestoreForFreshInstall()
        } else {
            print("📱 Existing install - using standard profile fetch...")
            await forceFetchProfile()
        }
    }
    
    /// Automatically restore purchases for fresh installs
    private func automaticRestoreForFreshInstall() async {
        print("🔄 Performing automatic restore for fresh install...")
        
        // 🛡️ SAFEGUARD: Double-check we haven't already attempted recently
        let lastAttemptKey = "subscription_last_restore_attempt"
        let lastAttemptTime = userDefaults.object(forKey: lastAttemptKey) as? Date ?? Date.distantPast
        let timeSinceLastAttempt = Date().timeIntervalSince(lastAttemptTime)
        
        if timeSinceLastAttempt < 300.0 { // Less than 5 minutes since last attempt
            print("⏸️ Skipping automatic restore - recent attempt \(Int(timeSinceLastAttempt))s ago")
            await forceFetchProfile() // Just fetch profile instead
            return
        }
        
        // Mark attempt time and flags to avoid repeated attempts
        userDefaults.set(Date(), forKey: lastAttemptKey)
        userDefaults.set(true, forKey: CacheKeys.hasAttemptedRestore)
        userDefaults.set(true, forKey: CacheKeys.isFirstLaunch)
        
        do {
            // Attempt to restore purchases - this syncs App Store receipts with Adapty
            let restoredProfile = try await Adapty.restorePurchases()
            
            await MainActor.run {
                self.profile = restoredProfile
                self.updatePremiumStatus(from: restoredProfile)
                self.isLoading = false
                self.cacheStatus()
            }
            
            let hasPremium = restoredProfile.accessLevels["premium"]?.isActive == true
            
            if hasPremium {
                print("✅ Automatic restore successful - found active premium subscription!")
                // Automatically enable folder management for restored premium users
                print("📁 SubscriptionService: Enabling folder management for automatically restored premium user")
                SettingsService.shared.isFolderManagementEnabled = true
            } else {
                print("ℹ️ Automatic restore completed - no active premium subscription found")
            }
            
        } catch {
            print("❌ Automatic restore failed: \(error)")
            print("   - Falling back to standard profile fetch...")
            
            // Fallback to normal profile fetch if restore fails
            await forceFetchProfile()
        }
    }
    
    /// Refresh subscription status when app returns from background
    func refreshOnAppDidBecomeActive() async {
        print("🔄 App became active - checking subscription status...")
        let previousPremiumStatus = isPremium
        
        // 🛡️ SAFEGUARD: Don't refresh immediately after launch to prevent duplicates
        let lastUpdate = userDefaults.object(forKey: CacheKeys.lastProfileUpdate) as? Date
        let timeSinceLastCheck = Date().timeIntervalSince(lastUpdate ?? Date.distantPast)
        if timeSinceLastCheck < 30.0 { // Less than 30 seconds since last check
            print("⏸️ Skipping background refresh - too soon after last check (\(Int(timeSinceLastCheck))s ago)")
            return
        }
        
        // Use regular profile fetch, not restoration for background checks
        await forceFetchProfile()
        
        // Log if status changed while app was in background
        if previousPremiumStatus != isPremium {
            print("🔄 Subscription status changed while app was in background: \(previousPremiumStatus) → \(isPremium)")
            
            // Post notification that subscription status changed
            NotificationCenter.default.post(
                name: NSNotification.Name("SubscriptionStatusChanged"),
                object: nil,
                userInfo: [
                    "previousStatus": previousPremiumStatus,
                    "newStatus": isPremium,
                    "context": "backgroundRefresh"
                ]
            )
        } else {
            print("✅ Subscription status unchanged after background refresh: \(isPremium)")
        }
    }
    
    /// Comprehensive subscription refresh - checks both Adapty and StoreKit, updates all local data
    func forceRefreshSubscriptionStatusWithFallback() async {
        print("🔄 Starting comprehensive subscription status refresh...")
        
        await MainActor.run {
            self.isLoading = true
        }
        
        // Try Adapty first
        let adaptySuccess = await refreshFromAdapty()
        
        // If Adapty fails, try StoreKit as fallback
        if !adaptySuccess {
            print("⚠️ Adapty failed, trying StoreKit fallback...")
            await refreshFromStoreKit()
        }
        
        // Always update UI and local data based on current status
        await updateLocalDataBasedOnSubscription()
        
        await MainActor.run {
            self.isLoading = false
            
            // Force UI refresh by posting notification
            NotificationCenter.default.post(
                name: .subscriptionStatusChanged,
                object: nil,
                userInfo: ["isPremium": self.isPremium, "forceUpdate": true]
            )
        }
        
        print("✅ Comprehensive subscription refresh completed: isPremium=\(isPremium)")
    }
    
    // MARK: - Private Refresh Methods
    
    private func refreshFromAdapty() async -> Bool {
        do {
            let fetchedProfile = try await Adapty.getProfile()
            await MainActor.run {
                self.profile = fetchedProfile
                self.updatePremiumStatus(from: fetchedProfile)
                self.cacheStatus()
            }
            print("✅ Successfully refreshed from Adapty: isPremium=\(isPremium)")
            return true
        } catch {
            print("❌ Failed to refresh from Adapty: \(error)")
            return false
        }
    }
    
    @available(iOS 15.0, *)
    private func refreshFromStoreKit() async {
        do {
            // Get current entitlements from StoreKit
            for await result in Transaction.currentEntitlements {
                let transaction = try checkVerified(result)
                
                // Check if any transaction represents an active subscription
                if transaction.revocationDate == nil {
                    print("🏪 StoreKit found active transaction: \(transaction.productID)")
                    
                    // Update status to premium if we find any active subscription
                    await MainActor.run {
                        let wasAlreadyPremium = self.isPremium
                        self.isPremium = true
                        self.cacheStatus()
                        
                        if !wasAlreadyPremium {
                            print("🆙 StoreKit confirmed premium status")
                        }
                    }
                    return
                }
            }
            
            // No active subscriptions found
            await MainActor.run {
                let wasPrevouslyPremium = self.isPremium
                self.isPremium = false
                self.cacheStatus()
                
                if wasPrevouslyPremium {
                    print("📉 StoreKit confirmed no active subscription")
                }
            }
            
        } catch {
            print("❌ StoreKit check failed: \(error)")
            // On error, assume not premium for safety
            await MainActor.run {
                self.isPremium = false
                self.cacheStatus()
            }
        }
    }
    
    @available(iOS 15.0, *)
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
    
    private func updateLocalDataBasedOnSubscription() async {
        // Trigger local data cleanup if user is no longer premium
        if !isPremium {
            // Post notification to trigger data cleanup
            NotificationCenter.default.post(
                name: .subscriptionDowngrade,
                object: nil,
                userInfo: ["isPremium": false]
            )
        }
    }
}

// MARK: - Extensions

extension Notification.Name {
    static let subscriptionStatusChanged = Notification.Name("subscriptionStatusChanged")
    static let subscriptionDowngrade = Notification.Name("subscriptionDowngrade")
}

// MARK: - Store Error Types

enum StoreError: Error {
    case failedVerification
}

// MARK: - AdaptyProfile Extensions

extension AdaptyProfile {
    /// Convenience property to check if user has premium access
    var hasPremiumAccess: Bool {
        return accessLevels["premium"]?.isActive == true
    }
}

