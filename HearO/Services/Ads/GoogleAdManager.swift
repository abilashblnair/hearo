import Foundation
import UIKit
import GoogleMobileAds
import AdSupport
import AppTrackingTransparency

class GoogleAdManager: NSObject, ObservableObject, AdManagerProtocol {
    // MARK: - Properties
    private var interstitialAd: InterstitialAd?
    private var onAdDismissedCompletion: ((Bool) -> Void)?
    private let adUnitID = "ca-app-pub-1055210520655693/8009263550"

    // MARK: - Published Properties
    @Published var isAdLoading: Bool = false
    @Published var lastAdLoadTime: Date?

    // MARK: - Computed Properties
    var isAdReady: Bool {
        return interstitialAd != nil
    }

    var getShouldShowAd: Bool {
        return isAdReady
    }

    // MARK: - Initialization
    override init() {
        super.init()
        setupAdManager()
    }

    private func setupAdManager() {
        print("🎯 GoogleAdManager: Initializing...")
        print("📱 Advertising ID: \(ASIdentifierManager.shared().advertisingIdentifier)")

        // Preload ad on initialization
        preloadAd()
    }

    // MARK: - Ad Loading
    func preloadAd() {
        guard !isAdLoading else {
            print("⏳ Ad already loading, skipping...")
            return
        }

        // Don't reload too frequently (minimum 30 seconds between loads)
        if let lastLoad = lastAdLoadTime,
           Date().timeIntervalSince(lastLoad) < 30 {
            print("⏸️ Skipping ad load - too recent (< 30s)")
            return
        }

        print("🚀 Starting interstitial ad load...")
        isAdLoading = true

        let request = createAdRequest()

        InterstitialAd.load(with: adUnitID, request: request) { [weak self] ad, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                self.isAdLoading = false
                self.lastAdLoadTime = Date()

                if let error = error {
                    self.handleAdLoadError(error)
                    return
                }

                guard let ad = ad else {
                    print("❌ No ad returned, but no error")
                    return
                }

                self.setupLoadedAd(ad)
            }
        }
    }

    private func createAdRequest() -> Request {
        let request = Request()

        // Configuration for ad request can be done here

        return request
    }

    private func setupLoadedAd(_ ad: InterstitialAd) {
        self.interstitialAd = ad
        self.interstitialAd?.fullScreenContentDelegate = self

        print("✅ Interstitial ad loaded successfully!")
        print("📊 Ad loaded at: \(Date())")

        // Optional: Log ad metadata - simplified logging to avoid API issues
        print("📋 Ad Response Info: \(ad.responseInfo)")
    }

    private func handleAdLoadError(_ error: Error) {
        print("❌ Failed to load interstitial ad")
        print("🔍 Error: \(error.localizedDescription)")
        print("🏷️ Domain: \((error as NSError).domain)")
        print("🔢 Code: \((error as NSError).code)")

        // Log specific error codes for debugging
        let nsError = error as NSError
        switch nsError.code {
        case 0: // kGADErrorInvalidRequest
            print("💡 Invalid request - check ad unit ID and request parameters")
        case 1: // kGADErrorNoFill
            print("💡 No ad inventory available - try again later")
        case 2: // kGADErrorNetworkError
            print("💡 Network error - check internet connection")
        case 3: // kGADErrorServerError
            print("💡 Server error - AdMob server issue")
        case 8: // kGADErrorInvalidArgument
            print("💡 Invalid argument - check implementation")
        default:
            print("💡 Other error - code: \(nsError.code)")
        }

        self.interstitialAd = nil
    }

    // MARK: - Ad Presentation
    func presentInterstitial(from rootViewController: UIViewController, onDismissed: @escaping (Bool) -> Void) {
        guard let interstitial = interstitialAd else {
            print("❌ No interstitial ad available to present")
            onDismissed(false) // Ad was not shown
            preloadNextAd() // Try to load next ad
            return
        }

        print("🎬 Presenting interstitial ad...")

        // Store completion handler
        onAdDismissedCompletion = onDismissed

        // Present the full-screen ad
        interstitial.present(from: rootViewController)

        // Clear the ad (it can only be used once)
        self.interstitialAd = nil
    }

    private func preloadNextAd() {
        // Delay next ad load slightly to avoid rapid requests
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.preloadAd()
        }
    }

    // MARK: - Legacy Support (for backward compatibility)
    func loadAd() {
        preloadAd()
    }

    func showAd(from rootViewController: UIViewController, onAdDismissed: @escaping () -> Void) {
        presentInterstitial(from: rootViewController) { wasShown in
            onAdDismissed() // Call legacy completion regardless of success
        }
    }
}

// MARK: - FullScreenContentDelegate
extension GoogleAdManager: FullScreenContentDelegate {

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("🎬 Interstitial ad will present full screen content")
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("❌ Interstitial ad failed to present")
        print("🔍 Error: \(error.localizedDescription)")

        // Notify completion that ad failed to show
        onAdDismissedCompletion?(false)
        onAdDismissedCompletion = nil

        // Preload next ad
        preloadNextAd()
    }

    func adWillDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("👋 Interstitial ad will dismiss")
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("✅ Interstitial ad dismissed")

        // Notify completion that ad was successfully shown and dismissed
        onAdDismissedCompletion?(true)
        onAdDismissedCompletion = nil

        // Preload next ad for future use
        preloadNextAd()
    }
}
