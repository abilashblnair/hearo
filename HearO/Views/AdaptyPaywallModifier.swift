import SwiftUI
import Adapty
import AdaptyUI

struct IdentifiableErrorWrapper: Identifiable {
    let id: String = UUID().uuidString
    let title: String
    let error: Error
}

// //⚠️ Implement ObserverModeResolver to work in ObserverMode
// class ObserverModeResolver: AdaptyObserverModeResolver {
//    func observerMode(
//        didInitiatePurchase product: AdaptyPaywallProduct,
//        onStartPurchase: @escaping () -> Void,
//        onFinishPurchase: @escaping () -> Void
//    ) {
//        // handle the purchase
//    }
// }

struct PaywallViewModifier: ViewModifier {
    private var isPresented: Binding<Bool>
    private var placementId: String
    @ObservedObject var subscriptionManager = SubscriptionManager.shared

    init(isPresented: Binding<Bool>, placementId: String) {
        self.isPresented = isPresented
        self.placementId = placementId
    }

    @State private var paywallConfig: AdaptyUI.PaywallConfiguration?

    @State private var alertError: IdentifiableErrorWrapper?
    @State private var alertPaywallError: IdentifiableErrorWrapper?

    @ViewBuilder
    @MainActor
    func contentOrSheet(content: Content) -> some View {
        if let paywallConfig {
            content
                .paywall(
                    isPresented: isPresented,
                    paywallConfiguration: paywallConfig,
                    // ⚠️ Pass AdaptyObserverModeResolver object to work in ObserverMode
                    // observerModeResolver: ObserverModeResolver(),
                    didFinishPurchase: {_, result in
                        print("🎯 AdaptyPaywallModifier: didFinishPurchase called with result: \(result)")
                        switch result {
                        case .success:
                            print("✅ AdaptyPaywallModifier: Purchase succeeded - dismissing paywall and showing success screen")
                            // Dismiss paywall immediately
                            isPresented.wrappedValue = false
                            // Show success screen for actual purchase
                            subscriptionManager.showSuccessViewForPurchase()
                            
                            // Automatically enable folder management for new premium users
                            print("📁 AdaptyPaywallModifier: Enabling folder management for new premium user")
                            SettingsService.shared.isFolderManagementEnabled = true
                            
                            // Force immediate update of subscription status
                            Task {
                                await subscriptionManager.forceRefreshSubscriptionStatus()
                            }
                        case .pending:
                            isPresented.wrappedValue = false
                            alertPaywallError = .init(title: "Purchase pending - requires user action", error: PurchaseError.pending("Purchase pending - requires user action"))
                        case .userCancelled:
                            isPresented.wrappedValue = false
                            alertPaywallError = .init(title: "User cancelled purchase", error: PurchaseError.userCancelled)
                        @unknown default:
                            break
                        }
                    },
                    didFailPurchase: { _, error in
                        print("❌ AdaptyPaywallModifier: didFailPurchase called with error: \(error)")
                        alertPaywallError = .init(title: "didFailPurchase error!", error: error)
                    },
                    didFinishRestore: { profile in
                        print("🔄 AdaptyPaywallModifier: didFinishRestore called")
                        print("📊 Restored profile premium status: \(profile.accessLevels["premium"]?.isActive == true)")
                        
                        // Check if restore was successful
                        if profile.accessLevels["premium"]?.isActive == true {
                            print("✅ AdaptyPaywallModifier: Restore successful - dismissing paywall and showing success")
                            // Successful restore - dismiss paywall and show success for user-initiated restore
                            isPresented.wrappedValue = false
                            subscriptionManager.showSuccessViewForPurchase()
                            
                            // Automatically enable folder management for restored premium users
                            print("📁 AdaptyPaywallModifier: Enabling folder management for restored premium user")
                            SettingsService.shared.isFolderManagementEnabled = true
                            
                            // Force immediate update of subscription status
                            Task {
                                await subscriptionManager.forceRefreshSubscriptionStatus()
                            }
                        } else {
                            print("❌ AdaptyPaywallModifier: Restore failed - no active premium subscription")
                            // Failed restore - show error
                            alertPaywallError = .init(title: "Unable to restore", error: PurchaseError.restoreFailed)
                        }
                    },
                    didFailRestore: { error in
                        print("❌ AdaptyPaywallModifier: didFailRestore called with error: \(error)")
                        alertPaywallError = .init(title: "didFailRestore error!", error: error)
                    },
                    didFailRendering: { error in
                        isPresented.wrappedValue = false
                        alertPaywallError = .init(title: "didFailRendering error!", error: error)
                    },
                    showAlertItem: $alertPaywallError,
                    showAlertBuilder: { errorItem in
                        Alert(
                            title: Text(errorItem.title),
                            message: Text("\(errorItem.error.localizedDescription)"),
                            dismissButton: .cancel()
                        )
                    }
                )

        } else {
            content
        }
    }

    func body(content: Content) -> some View {
        contentOrSheet(content: content)
            .task {
                do {
                    // Add retry logic for fresh installs
                    let paywall = try await getPaywallWithRetry(placementId: placementId)
                    paywallConfig = try await AdaptyUI.getPaywallConfiguration(forPaywall: paywall)
                } catch {
                    alertError = .init(title: "getPaywallAndConfig error!", error: error)
                }
            }
            .alert(item: $alertError) { errorWrapper in
                Alert(
                    title: Text(errorWrapper.title),
                    message: Text("\(errorWrapper.error.localizedDescription)"),
                    dismissButton: .cancel()
                )
            }
    }
    
    // Helper method to retry paywall loading for fresh installs
    private func getPaywallWithRetry(placementId: String, maxRetries: Int = 3) async throws -> AdaptyPaywall {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                let paywall = try await Adapty.getPaywall(placementId: placementId)
                return paywall
            } catch {
                lastError = error
                
                // For fresh installs, wait a bit and retry
                if attempt < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000) // 1-3 seconds delay
                }
            }
        }
        
        throw lastError ?? NSError(domain: "AdaptyPaywallModifier", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load paywall after \(maxRetries) attempts"])
    }
}

extension View {
    func paywall(isPresented: Binding<Bool>, placementId: String) -> some View {
        modifier(
            PaywallViewModifier(
                isPresented: isPresented,
                placementId: placementId
            )
        )
    }
}

