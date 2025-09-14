//
//  HearOApp.swift
//  HearO
//
//  Created by Abilash Balasubramanian on 12/08/25.
//

import SwiftUI
import SwiftData
import UIKit
import GoogleMobileAds
import Adapty
import AdaptyUI

@main
struct HearOApp: App {
    init() {
        // Configure Google Mobile Ads
        MobileAds.shared.start(completionHandler: nil)
        
        // Configure and activate Adapty SDK asynchronously with retry for fresh installs
        Task {
            await HearOApp.initializeAdapty()
        }
    }

    @StateObject private var di = ServiceContainer.create()
    @State private var showSplash = true
    @State private var showTutorial = !UserDefaults.standard.bool(forKey: "didShowTutorial")
    
    // MARK: - Adapty Initialization
    
    private static func initializeAdapty() async {
        do {
            let configurationBuilder = AdaptyConfiguration
                .builder(withAPIKey: "public_live_XObF89P2.eihC2JCKRoq5S1t9lhHv")
                .with(logLevel: .verbose) // recommended for development
                .with(observerMode: false) // Set to true if you handle purchases yourself
            
            let config = configurationBuilder.build()
            try await Adapty.activate(with: config)
            try await AdaptyUI.activate()
            
            print("✅ Adapty successfully initialized")
            
        } catch {
            print("❌ Adapty activation failed: \(error)")
            
            // Retry once for fresh installs
            try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
            do {
                let configurationBuilder = AdaptyConfiguration
                    .builder(withAPIKey: "public_live_XObF89P2.eihC2JCKRoq5S1t9lhHv")
                    .with(logLevel: .verbose)
                    .with(observerMode: false)
                
                let config = configurationBuilder.build()
                try await Adapty.activate(with: config)
                try await AdaptyUI.activate()
                
                print("✅ Adapty initialized on retry")
            } catch {
                print("❌ Adapty retry failed: \(error)")
            }
        }
    }
    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView(isActive: $showSplash)
                } else if showTutorial {
                    TutorialView(isPresented: $showTutorial)
                } else {
                    HomeView()
                }
            }
            .environmentObject(di)
            .modelContainer(LocalDataManager.shared.modelContainer)
            .onAppear {
                // Comprehensive subscription status refresh on app launch
                Task { @MainActor in
                    await SubscriptionManager.shared.forceRefreshSubscriptionStatus()
                }
                
                // Set up app lifecycle observers for subscription refresh
                setupAppLifecycleObservers()
            }
        }
    }
    
    // MARK: - App Lifecycle Management
    
    /// Set up observers for app lifecycle events to refresh subscription status
    private func setupAppLifecycleObservers() {
        // Refresh subscription when app becomes active from background
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                print("🔄 App became active from background - refreshing subscription status")
                await SubscriptionManager.shared.refreshOnAppDidBecomeActive()
            }
        }
        
        // Optional: Also refresh when app will enter foreground (earlier trigger)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                print("🌅 App will enter foreground - preparing subscription refresh")
                // Use lighter refresh method for foreground preparation
                await SubscriptionManager.shared.refreshOnAppLaunch()
            }
        }
        
        print("✅ App lifecycle observers set up for subscription refresh")
    }
}
