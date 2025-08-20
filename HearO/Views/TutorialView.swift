import Foundation
import SwiftUI
import UIKit

struct TutorialView: View {
    @Binding var isPresented: Bool
    @State private var page = 0
    @StateObject private var vm = TutorialViewModel()

    // Dynamic background gradients per page
    private let gradients: [(Color, Color)] = [
        (Color(red: 0.99, green: 0.88, blue: 0.90), Color(red: 1.00, green: 0.75, blue: 0.68)), // pink → orange
        (Color(red: 0.88, green: 0.93, blue: 1.00), Color(red: 0.80, green: 0.86, blue: 1.00)), // light blue → periwinkle
        (Color(red: 0.88, green: 1.00, blue: 0.94), Color(red: 0.78, green: 0.96, blue: 0.92))  // mint → teal
    ]

    var body: some View {
        ZStack {
            // Animated gradient per page
            let pair = gradients[vm.pages.isEmpty ? 0 : page % gradients.count]
            LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.45), value: page)

            VStack(spacing: 0) {
                // Top bar with Skip and progress
                HStack(alignment: .center) {
                    ProgressView(value: vm.pages.isEmpty ? 0 : Double(page + 1), total: Double(max(vm.pages.count, 1)))
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                        .frame(maxWidth: .infinity)
                        .animation(.easeInOut(duration: 0.3), value: page)
                    Button("Skip") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        isPresented = false
                        UserDefaults.standard.set(true, forKey: "didShowTutorial")
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundColor(.blue)
                    .padding(.leading, 12)
                }
                .padding([.top, .horizontal])

                Spacer(minLength: 12)

                if !vm.pages.isEmpty {
                    // Pager
                    TabView(selection: $page) {
                        ForEach(Array(vm.pages.enumerated()), id: \.offset) { idx, p in
                            OnboardingCard(imageName: p.imageName, title: p.title, description: p.description, isCurrent: idx == page)
                                .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 60 : 20)
                                .tag(idx)
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: page)
                    .sensoryFeedback(.selection, trigger: page)

                    // Dots indicator
                    PageIndicator(count: vm.pages.count, index: page)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    // CTA
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if page < vm.pages.count - 1 {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { page += 1 }
                        } else {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            isPresented = false
                            UserDefaults.standard.set(true, forKey: "didShowTutorial")
                        }
                    }) {
                        Text(page == vm.pages.count - 1 ? "Get Started" : "Next")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
                            .contentTransition(.opacity)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading tutorial…")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        // Subtle selection haptic when page changes (fallback)
        .onChange(of: page) { _, _ in UISelectionFeedbackGenerator().selectionChanged() }
    }
}

// MARK: - Components
private struct OnboardingCard: View {
    let imageName: String
    let title: String
    let description: String
    var isCurrent: Bool
    @State private var appear = false

    var body: some View {
        VStack(spacing: 20) {
            // Image with entrance, scale and depth
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(height: 260)
                .scaleEffect(appear ? (isCurrent ? 1.0 : 0.97) : 0.95)
                .opacity(appear ? 1.0 : 0)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 8)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: isCurrent)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: appear)

            VStack(spacing: 10) {
                Text(title)
                    .font(.system(.title, design: .rounded).bold())
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.top, 8)
        .scaleEffect(isCurrent ? 1.0 : 0.98)
        .opacity(isCurrent ? 1.0 : 0.9)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: isCurrent)
        .onAppear { appear = true }
        .onDisappear { appear = false }
        .transition(.asymmetric(insertion: .opacity.combined(with: .scale), removal: .opacity))
    }
}

private struct PageIndicator: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                Capsule()
                    .fill(i == index ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: i == index ? 22 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: index)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1) of \(count)")
    }
}
