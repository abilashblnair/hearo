import SwiftUI

struct SplashView: View {
    @Binding var isActive: Bool
    @State private var animateWaves = false
    @State private var animateCircles = false
    @State private var textAnimationPhase = 0
    @State private var showSubtitle = false
    @State private var finalScale: CGFloat = 1.0
    
    private let characters = Array("AuryO")
    
    var body: some View {
        ZStack {
            // Dynamic gradient background
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.6),
                    Color.purple.opacity(0.4),
                    Color.pink.opacity(0.3),
                    Color.orange.opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .blur(radius: animateWaves ? 20 : 0)
            .animation(.easeInOut(duration: 2), value: animateWaves)
            
            // Glass effect background
            RoundedRectangle(cornerRadius: 30)
                .fill(.ultraThinMaterial)
                .frame(width: 320, height: 400)
                .overlay(
                    RoundedRectangle(cornerRadius: 30)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .scaleEffect(finalScale)
                .animation(.spring(response: 1.2, dampingFraction: 0.8), value: finalScale)
            
            VStack(spacing: 40) {
                // Hearing Animation Container
                ZStack {
                    // Outer expanding circles (sound waves)
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [.blue.opacity(0.3), .purple.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                            .frame(width: 60 + CGFloat(index * 30), height: 60 + CGFloat(index * 30))
                            .scaleEffect(animateCircles ? 1.5 + CGFloat(index) * 0.3 : 1.0)
                            .opacity(animateCircles ? 0 : 0.7)
                            .animation(
                                .easeOut(duration: 2)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.2),
                                value: animateCircles
                            )
                    }
                    
                    // Central hearing icon with dynamic waves
                    ZStack {
                        // Background glow
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.blue.opacity(0.3), .clear],
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: 40
                                )
                            )
                            .frame(width: 80, height: 80)
                            .scaleEffect(animateWaves ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateWaves)
                        
                        // Ear icon with sound waves
                        HStack(spacing: 4) {
                            // Ear icon
                            Image(systemName: "ear.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            // Dynamic sound waves
                            VStack(spacing: 2) {
                                ForEach(0..<4, id: \.self) { index in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(
                                            LinearGradient(
                                                colors: [.blue, .purple.opacity(0.8)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(
                                            width: animateWaves ? CGFloat(8 + index * 4) : CGFloat(4 + index * 2),
                                            height: 3
                                        )
                                        .animation(
                                            .easeInOut(duration: 0.6)
                                            .repeatForever(autoreverses: true)
                                            .delay(Double(index) * 0.1),
                                            value: animateWaves
                                        )
                                }
                            }
                        }
                    }
                }
                
                // Animated Title
                HStack(spacing: 4) {
                    ForEach(0..<characters.count, id: \.self) { index in
                        Text(String(characters[index]))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple, .pink],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(textAnimationPhase > index ? 1.2 : 0.1)
                            .rotationEffect(.degrees(textAnimationPhase > index ? 0 : 360))
                            .opacity(textAnimationPhase > index ? 1 : 0)
                            .offset(y: textAnimationPhase > index ? 0 : -50)
                            .animation(
                                .spring(response: 0.6, dampingFraction: 0.7)
                                .delay(Double(index) * 0.1),
                                value: textAnimationPhase
                            )
                    }
                }
                
                // Animated subtitle
                Text("Record. Transcribe. Remember.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.secondary, .primary.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(showSubtitle ? 1 : 0)
                    .offset(y: showSubtitle ? 0 : 20)
                    .animation(.easeOut(duration: 0.8).delay(1.0), value: showSubtitle)
            }
            .scaleEffect(finalScale)
        }
        .onAppear {
            startAnimationSequence()
        }
    }
    
    private func startAnimationSequence() {
        // Start background and wave animations
        withAnimation {
            animateWaves = true
            animateCircles = true
        }
        
        // Start text blast animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation {
                textAnimationPhase = characters.count
            }
        }
        
        // Show subtitle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation {
                showSubtitle = true
            }
        }
        
        // Final scale and transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.9)) {
                finalScale = 1.1
            }
        }
        
        // Dismiss splash
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeInOut(duration: 0.8)) {
                finalScale = 0.8
                isActive = false
            }
        }
    }
}
