import SwiftUI
import UIKit

enum GlassDesign {
    static func applyGlobalAppearance() {
        // Tab bar glass appearance
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        tabAppearance.backgroundColor = .clear
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        // Navigation bar glass appearance
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        navAppearance.backgroundColor = .clear
        navAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.label
        ]
        navAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.label
        ]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
    }
}

private struct GlassBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat?

    func body(content: Content) -> some View {
        if let cornerRadius {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                )
        } else {
            content
                .background(.ultraThinMaterial)
        }
    }
}

extension View {
    func glassBackground(cornerRadius: CGFloat? = nil) -> some View {
        modifier(GlassBackgroundModifier(cornerRadius: cornerRadius))
    }
}


