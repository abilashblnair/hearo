//
//  HearOApp.swift
//  HearO
//
//  Created by Abilash Balasubramanian on 12/08/25.
//

import SwiftUI
import SwiftData

@main
struct HearOApp: App {
    @StateObject private var di = ServiceContainer.create()
    @State private var showSplash = true
    @State private var showTutorial = !UserDefaults.standard.bool(forKey: "didShowTutorial")
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
        }
    }
}
