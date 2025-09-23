import SwiftUI

/// A star rating view component that shows interactive stars for rating
struct StarRatingView: View {
    @Binding var rating: Int
    let maxRating: Int = 5

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...maxRating, id: \.self) { star in
                Button(action: {
                    rating = star
                }) {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.largeTitle)
                        .foregroundColor(star <= rating ? .yellow : .gray)
                        .scaleEffect(star <= rating ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: rating)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

/// App Rating Alert View that shows when user hasn't rated the app
struct AppRatingAlertView: View {
    @Binding var isPresented: Bool
    @State private var selectedRating: Int = 0
    @AppStorage("hasRatedApp") private var hasRatedApp: Bool = false

    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // Alert content
            VStack(spacing: 20) {
                // App icon placeholder
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "waveform")
                            .font(.largeTitle)
                            .foregroundColor(.accentColor)
                    )

                // Title
                VStack(spacing: 8) {
                    Text("Enjoying")
                        .font(.title2)
                        .fontWeight(.medium)
                    + Text(" AuryO")
                        .font(.title2)
                        .fontWeight(.bold)
                    + Text("?")
                        .font(.title2)
                        .fontWeight(.medium)

                    Text("Tap a star to rate it on the\nApp Store.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Star rating
                StarRatingView(rating: $selectedRating)
                    .padding(.vertical, 8)

                // Buttons
                HStack(spacing: 0) {
                    // Cancel button
                    Button("Cancel") {
                        isPresented = false
                    }
                    .font(.body)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)

                    // Divider
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 0.5)
                        .frame(maxHeight: .infinity)

                    // Submit button
                    Button("Submit") {
                        submitRating()
                    }
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(selectedRating > 0 ? .blue : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .disabled(selectedRating == 0)
                }
                .frame(height: 44)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
            .padding(.horizontal, 40)
        }
    }

    private func submitRating() {
        guard selectedRating > 0 else { return }

        // Mark as rated to prevent showing again
        hasRatedApp = true

        // Close the alert
        isPresented = false

        // Open App Store for rating
        AppConfigManager.shared.openAppStoreForRating()
    }
}

#Preview {
    AppRatingAlertView(isPresented: .constant(true))
}
