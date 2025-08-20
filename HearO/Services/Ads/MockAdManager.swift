import Foundation
import UIKit

class MockAdManager: NSObject, ObservableObject, AdManagerProtocol {
    // MARK: - Published Properties
    @Published var isAdLoading: Bool = false
    @Published var lastAdLoadTime: Date?

    // MARK: - Computed Properties
    var isAdReady: Bool {
        // Simulate having ads ready 70% of the time
        return Bool.random() && Date().timeIntervalSince(lastAdLoadTime ?? .distantPast) > 30
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
        print("🎯 MockAdManager: Initializing...")
        // Preload ad on initialization
        preloadAd()
    }

    // MARK: - Ad Loading
    func preloadAd() {
        guard !isAdLoading else {
            print("⏳ Mock ad already loading, skipping...")
            return
        }

        // Don't reload too frequently (minimum 30 seconds between loads)
        if let lastLoad = lastAdLoadTime,
           Date().timeIntervalSince(lastLoad) < 30 {
            print("⏸️ Skipping mock ad load - too recent (< 30s)")
            return
        }

        print("🚀 Starting mock interstitial ad load...")
        isAdLoading = true

        // Simulate ad loading delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            
            self.isAdLoading = false
            self.lastAdLoadTime = Date()
            
            // Simulate success most of the time
            if Bool.random() {
                print("✅ Mock interstitial ad loaded successfully!")
            } else {
                print("❌ Mock ad failed to load (simulated)")
            }
        }
    }

    // MARK: - Ad Presentation
    func presentInterstitial(from rootViewController: UIViewController, onDismissed: @escaping (Bool) -> Void) {
        guard isAdReady else {
            print("❌ No mock interstitial ad available to present")
            onDismissed(false) // Ad was not shown
            preloadNextAd() // Try to load next ad
            return
        }

        print("🎬 Presenting mock interstitial ad...")

        // Simulate showing ad with delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("🎬 Mock ad will present full screen content")
            
            // Simulate ad display time (2-4 seconds)
            let displayTime = Double.random(in: 2...4)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + displayTime) {
                print("✅ Mock interstitial ad dismissed")
                onDismissed(true) // Ad was successfully shown
                self.preloadNextAd()
            }
        }
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
