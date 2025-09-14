import SwiftUI
import Adapty
import AdaptyUI

/// Premium upgrade paywall view with corrected structure
struct PaywallView: View {
    
    // MARK: - Properties
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var subscriptionService = SubscriptionService.shared
    @StateObject private var featureManager = FeatureManager.shared
    @State private var paywallProducts: [AdaptyPaywallProduct] = []
    
    @State private var selectedProduct: AdaptyPaywallProduct?
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    
    let triggerFeature: PremiumFeature?
    
    // MARK: - Initialization
    
    init(triggerFeature: PremiumFeature? = nil) {
        self.triggerFeature = triggerFeature
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [.blue.opacity(0.6), .purple.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    headerView
                    
                    Spacer()
                    
                    if subscriptionService.isLoading {
                        ProgressView("Loading plans...")
                            .foregroundColor(.white)
                    } else {
                        subscriptionOptionsView
                    }
                    
                    Spacer()
                    
                    actionButtonsView
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .alert("Purchase Failed", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .task {
            await loadPaywallAndProducts()
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        VStack(spacing: 12) {
            Image(systemName: getFeatureIcon())
                .font(.system(size: 60))
                .foregroundColor(.white)
            
            Text("Upgrade to Premium")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(getFeatureDescription())
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private var subscriptionOptionsView: some View {
        VStack(spacing: 16) {
            if !paywallProducts.isEmpty {
                Text("Choose Your Plan")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                VStack(spacing: 12) {
                    ForEach(paywallProducts, id: \.vendorProductId) { product in
                        SubscriptionOptionCard(
                            product: product,
                            isSelected: selectedProduct?.vendorProductId == product.vendorProductId
                        ) {
                            selectedProduct = product
                        }
                    }
                }
            }
        }
    }
    
    private var actionButtonsView: some View {
        VStack(spacing: 16) {
            // Main purchase button
            Button {
                Task {
                    await handlePurchase()
                }
            } label: {
                HStack {
                    if isPurchasing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    
                    Text(isPurchasing ? "Processing..." : "Start Premium")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.white)
                .foregroundColor(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isPurchasing || selectedProduct == nil)
            
            // Secondary actions
            HStack(spacing: 20) {
                Button("Restore Purchases") {
                    Task {
                        let result = await subscriptionService.restorePurchases()
                        await MainActor.run {
                            switch result {
                            case .success(let profile):
                                if profile.accessLevels["premium"]?.isActive == true {
                                    print("✅ PaywallView: Restore succeeded - triggering success screen")
                                    // Trigger the beautiful success screen instead of basic alert
                                    SubscriptionManager.shared.showSubscriptionSuccessView = true
                                    
                                    // Force immediate update of subscription status
                                    Task {
                                        await SubscriptionManager.shared.forceRefreshSubscriptionStatus()
                                    }
                                    
                                    // Dismiss the PaywallView
                                    dismiss()
                                } else {
                                    errorMessage = "No active premium subscription found to restore"
                                    showError = true
                                }
                            case .failure(let error):
                                errorMessage = "Restore failed: \(error.localizedDescription)"
                                showError = true
                            }
                        }
                    }
                }
                .foregroundColor(.white.opacity(0.8))
                
                Button("Terms & Privacy") {
                    // Handle terms and privacy
                }
                .foregroundColor(.white.opacity(0.8))
            }
            .font(.caption)
        }
    }
    
    // MARK: - Private Methods
    
    private func loadPaywallAndProducts() async {
        await subscriptionService.loadPaywall()
        
        if let paywall = subscriptionService.paywall {
            do {
                let products = try await Adapty.getPaywallProducts(paywall: paywall)
                await MainActor.run {
                    self.paywallProducts = products
                    if let firstProduct = products.first {
                        self.selectedProduct = firstProduct
                    }
                }
            } catch {
                print("Failed to load paywall products: \(error)")
                await MainActor.run {
                    self.errorMessage = "Failed to load subscription options"
                    self.showError = true
                }
            }
        }
    }
    
    private func handlePurchase() async {
        guard let product = selectedProduct else { return }
        
        isPurchasing = true
        defer { isPurchasing = false }
        
        do {
            let result = try await Adapty.makePurchase(product: product)
            
            if result.profile?.accessLevels["premium"]?.isActive == true {
                await MainActor.run {
                    print("✅ PaywallView: Purchase succeeded - triggering success screen")
                    // Show success view for actual purchase (not status refresh)
                    SubscriptionManager.shared.showSuccessViewForPurchase()
                    
                    // Force immediate update of subscription status
                    Task {
                        await SubscriptionManager.shared.forceRefreshSubscriptionStatus()
                    }
                    
                    // Dismiss the PaywallView
                    dismiss()
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func getFeatureIcon() -> String {
        switch triggerFeature {
        case .unlimitedDuration: return "timer"
        case .unlimitedRecordings: return "calendar"
        case .allLanguages: return "globe"
        case .export: return "square.and.arrow.up"
        case .unlimitedHistory: return "clock"
        case .folderManagement: return "folder"
        case .noAds: return "eye.slash"
        case .earlyAccess: return "star"
        case .none: return "star.fill"
        }
    }
    
    private func getFeatureDescription() -> String {
        switch triggerFeature {
        case .unlimitedDuration:
            return "Record for unlimited duration without restrictions"
        case .unlimitedRecordings:
            return "Create unlimited recordings every day"
        case .allLanguages:
            return "Access all languages and translation features"
        case .export:
            return "Export your recordings as text, PDF, and more"
        case .unlimitedHistory:
            return "Keep your recordings forever with unlimited history"
        case .folderManagement:
            return "Organize your recordings with custom folders"
        case .noAds:
            return "Enjoy an ad-free recording experience"
        case .earlyAccess:
            return "Get early access to new features"
        case .none:
            return "Unlock all premium features and enhance your experience"
        }
    }
}

// MARK: - Subscription Option Card

struct SubscriptionOptionCard: View {
    let product: AdaptyPaywallProduct
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.localizedTitle)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if !product.localizedDescription.isEmpty {
                        Text(product.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(product.localizedPrice ?? "$0.00")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    if let period = product.subscriptionPeriod {
                        Text("per \(formatSubscriptionPeriod(period))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .gray)
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatSubscriptionPeriod(_ period: AdaptySubscriptionPeriod) -> String {
        switch period.unit {
        case .day:
            return period.numberOfUnits == 1 ? "day" : "\(period.numberOfUnits) days"
        case .week:
            return period.numberOfUnits == 1 ? "week" : "\(period.numberOfUnits) weeks"
        case .month:
            return period.numberOfUnits == 1 ? "month" : "\(period.numberOfUnits) months"
        case .year:
            return period.numberOfUnits == 1 ? "year" : "\(period.numberOfUnits) years"
        case .unknown:
            return "period"
        @unknown default:
            return "period"
        }
    }
}

// MARK: - Preview

struct PaywallView_Previews: PreviewProvider {
    static var previews: some View {
        PaywallView(triggerFeature: .export)
    }
}
