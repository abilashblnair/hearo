import SwiftUI

/// Beautiful success screen shown after successful premium subscription purchase
struct SubscriptionSuccessView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    @State private var showContent = false
    @State private var showCheckmark = false
    @State private var showFeatures = false
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            // Dynamic gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.purple.opacity(0.8),
                    Color.blue.opacity(0.9),
                    Color.indigo.opacity(0.8)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .overlay(
                // Animated particles background
                ParticlesView()
                    .opacity(0.3)
            )
            
            // Debug indicator in top corner
            
            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 60)
                    
                    // Success animation
                    VStack(spacing: 24) {
                        // Animated checkmark
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 120, height: 120)
                                .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulseAnimation)
                            
                            Circle()
                                .fill(Color.white)
                                .frame(width: 100, height: 100)
                                .scaleEffect(showCheckmark ? 1.0 : 0.5)
                                .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.2), value: showCheckmark)
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.purple)
                                .scaleEffect(showCheckmark ? 1.0 : 0.1)
                                .animation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.4), value: showCheckmark)
                        }
                        
                        // Crown icon
                        Image(systemName: "crown.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.yellow)
                            .shadow(color: .yellow.opacity(0.5), radius: 10)
                            .scaleEffect(showContent ? 1.0 : 0.1)
                            .animation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.6), value: showContent)
                    }
                    
                    // Success content
                    VStack(spacing: 16) {
                        Text("Welcome to Premium!")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 30)
                            .animation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.8), value: showContent)
                        
                        Text("Your subscription is now active.\nEnjoy unlimited access to all premium features!")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 20)
                            .animation(.spring(response: 0.8, dampingFraction: 0.8).delay(1.0), value: showContent)
                    }
                    .padding(.horizontal, 32)
                    
                    // Premium features list
                    VStack(spacing: 16) {
                        ForEach(Array(premiumFeatures.enumerated()), id: \.offset) { index, feature in
                            FeatureRow(
                                icon: feature.icon,
                                title: feature.title,
                                description: feature.description
                            )
                            .opacity(showFeatures ? 1 : 0)
                            .offset(x: showFeatures ? 0 : -50)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(1.2 + Double(index) * 0.1), value: showFeatures)
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Action button - user must tap to continue
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        print("🎉 User tapped 'Start Exploring' - dismissing success view")
                        subscriptionManager.dismissSuccessView()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.title3)
                            Text("Start Exploring")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundColor(.purple)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        )
                    }
                    .buttonStyle(PressableButtonStyle())
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 30)
                    .animation(.spring(response: 0.8, dampingFraction: 0.8).delay(1.8), value: showContent)
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            print("🎉 SubscriptionSuccessView appeared!")
            startAnimations()
        }
        .onDisappear {
            print("🎉 SubscriptionSuccessView disappeared")
        }
    }
    
    private func startAnimations() {
        pulseAnimation = true
        
        withAnimation {
            showCheckmark = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation {
                showContent = true
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation {
                showFeatures = true
            }
        }
    }
    
    private var premiumFeatures: [PremiumFeatureItem] {
        [
            PremiumFeatureItem(
                icon: "infinity.circle.fill",
                title: "Unlimited Recordings",
                description: "Record as much as you want without limits"
            ),
            PremiumFeatureItem(
                icon: "globe.americas.fill",
                title: "All Languages",
                description: "Transcribe in 50+ languages worldwide"
            ),
            PremiumFeatureItem(
                icon: "square.and.arrow.up.circle.fill",
                title: "Export & Share",
                description: "Export transcripts to PDF, Word, and more"
            ),
            PremiumFeatureItem(
                icon: "folder.fill.badge.plus",
                title: "Smart Organization",
                description: "Create and manage unlimited folders"
            ),
            PremiumFeatureItem(
                icon: "eye.slash.circle.fill",
                title: "Ad-Free Experience",
                description: "Enjoy the app without any interruptions"
            )
        ]
    }
}

// MARK: - Supporting Views

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            // Feature icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.white)
            }
            
            // Feature content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
                .backdrop(BlurView(style: .systemUltraThinMaterial))
        )
    }
}

struct ParticlesView: View {
    @State private var animateParticles = false
    
    var body: some View {
        ZStack {
            ForEach(0..<20) { index in
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: CGFloat.random(in: 2...8), height: CGFloat.random(in: 2...8))
                    .position(
                        x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                        y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                    )
                    .animation(
                        .linear(duration: Double.random(in: 10...20))
                        .repeatForever(autoreverses: false),
                        value: animateParticles
                    )
            }
        }
        .onAppear {
            animateParticles = true
        }
    }
}

struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension View {
    func backdrop<Content: View>(_ content: Content) -> some View {
        self.background(content)
    }
}

// MARK: - Data Models

struct PremiumFeatureItem {
    let icon: String
    let title: String
    let description: String
}

// MARK: - Previews

struct SubscriptionSuccessView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionSuccessView()
            .environmentObject(SubscriptionManager.shared)
    }
}
