import Foundation
import Combine
import Adapty

/// Enhanced subscription manager that works with both custom paywall and AdaptyUI
@MainActor
final class SubscriptionManager: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = SubscriptionManager()
    
    // MARK: - Published Properties
    
    /// Whether to show subscription success view
    @Published var showSubscriptionSuccessView = false {
        didSet {
            print("🎯 SubscriptionManager.showSubscriptionSuccessView changed to: \(showSubscriptionSuccessView)")
        }
    }
    
    /// Current subscription status (delegates to SubscriptionService)
    @Published private(set) var isPremium: Bool = false
    
    /// Whether subscription status is currently being loaded
    @Published private(set) var isLoading: Bool = true
    
    /// Current subscription profile
    @Published private(set) var profile: AdaptyProfile?
    
    // MARK: - Private Properties
    
    private let subscriptionService = SubscriptionService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        setupSubscriptionServiceObservers()
    }
    
    // MARK: - Private Methods
    
    private func setupSubscriptionServiceObservers() {
        // Sync with existing SubscriptionService
        subscriptionService.$isPremium
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPremium)
        
        subscriptionService.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)
        
        subscriptionService.$profile
            .receive(on: DispatchQueue.main)
            .assign(to: &$profile)
        
        // Listen for subscription status changes - but don't auto-show success view
        NotificationCenter.default.publisher(for: .subscriptionStatusChanged)
            .sink { [weak self] notification in
                guard let self = self,
                      let isPremium = notification.userInfo?["isPremium"] as? Bool else { return }
                
                // Just log the status change - success view is handled by purchase flows only
                print("📊 Subscription status changed: isPremium=\(isPremium)")
                
                // Note: Success view is only shown for actual purchases/restores, not status refreshes
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Fetch the current subscription profile
    func fetchProfile() async {
        await subscriptionService.fetchProfile()
    }
    
    /// Make a purchase using the provided paywall product
    func makePurchase(product: AdaptyPaywallProduct) async -> Result<AdaptyPurchaseResult, Error> {
        return await subscriptionService.makePurchase(product: product)
    }
    
    /// Restore previous purchases
    func restorePurchases() async -> Result<AdaptyProfile, Error> {
        let result = await subscriptionService.restorePurchases()
        
        // If restore was successful and user has premium, trigger UI updates
        if case .success(let profile) = result,
           profile.accessLevels["premium"]?.isActive == true {
            await forceRefreshSubscriptionStatus()
        }
        
        return result
    }
    
    /// Refresh subscription status on app launch
    func refreshOnAppLaunch() async {
        await subscriptionService.refreshOnAppLaunch()
    }
    
    /// Refresh subscription status when app becomes active from background
    func refreshOnAppDidBecomeActive() async {
        await subscriptionService.refreshOnAppDidBecomeActive()
    }
    
    /// Force comprehensive subscription status refresh with StoreKit fallback
    func forceRefreshSubscriptionStatus() async {
        await subscriptionService.forceRefreshSubscriptionStatusWithFallback()
    }
    
    /// Show success view for actual purchases (not status refreshes)
    func showSuccessViewForPurchase() {
        print("🎉 Showing success view for actual purchase/restore")
        showSubscriptionSuccessView = true
    }
    
    /// Manually dismiss success view
    func dismissSuccessView() {
        showSubscriptionSuccessView = false
    }
    
    /// Test method to manually show success view
    func testShowSuccessView() {
        print("🧪 Test: Manually showing success view")
        showSubscriptionSuccessView = true
        
        // Auto-dismiss after 5 seconds for testing
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if self.showSubscriptionSuccessView {
                print("🧪 Test: Auto-dismissing success view after 5 seconds")
                self.showSubscriptionSuccessView = false
            }
        }
    }
    
    /// Check if user has specific access level
    func hasAccessLevel(_ accessLevelId: String) -> Bool {
        return profile?.accessLevels[accessLevelId]?.isActive == true
    }
    
    /// Get expiry date for access level
    func getExpiryDate(for accessLevelId: String) -> Date? {
        return profile?.accessLevels[accessLevelId]?.expiresAt
    }
}

// MARK: - Purchase Errors

enum PurchaseError: LocalizedError {
    case pending(String)
    case userCancelled
    case restoreFailed
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .pending(let message):
            return message
        case .userCancelled:
            return "Purchase was cancelled by the user"
        case .restoreFailed:
            return "Failed to restore previous purchases"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
}

