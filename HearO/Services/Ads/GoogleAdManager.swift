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

        // Preload ad on initialization
        preloadAd()
    }

    // MARK: - Ad Loading
    func preloadAd() {
        guard !isAdLoading else {
            return
        }

        // Don't reload too frequently (minimum 30 seconds between loads)
        if let lastLoad = lastAdLoadTime,
           Date().timeIntervalSince(lastLoad) < 30 {
            return
        }

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


        // Optional: Log ad metadata - simplified logging to avoid API issues
    }

    private func handleAdLoadError(_ error: Error) {

        // Log specific error codes for debugging
        let nsError = error as NSError
        switch nsError.code {
        case 0, 1, 2, 3, 8: // Known GAD error codes
            break
        default:
            break
        }

        self.interstitialAd = nil
    }

    // MARK: - Ad Presentation
    func presentInterstitial(from rootViewController: UIViewController, onDismissed: @escaping (Bool) -> Void) {
        guard let interstitial = interstitialAd else {
            onDismissed(false) // Ad was not shown
            preloadNextAd() // Try to load next ad
            return
        }


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
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {

        // Notify completion that ad failed to show
        onAdDismissedCompletion?(false)
        onAdDismissedCompletion = nil

        // Preload next ad
        preloadNextAd()
    }

    func adWillDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {

        // Notify completion that ad was successfully shown and dismissed
        onAdDismissedCompletion?(true)
        onAdDismissedCompletion = nil

        // Preload next ad for future use
        preloadNextAd()
    }
}
