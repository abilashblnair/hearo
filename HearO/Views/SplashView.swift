import SwiftUI

struct SplashView: View {
    @Binding var isActive: Bool
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 32) {
                Image(systemName: "waveform")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.accentColor)
                Text("HearO")
                    .font(.largeTitle.bold())
                Text("Your AI-powered meeting assistant")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { isActive = false }
            }
        }
    }
}
