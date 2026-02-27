import SwiftUI

/// The first screen in the onboarding flow showing the app's value proposition.
///
/// Displays the app logo, tagline, carousel cards explaining core features,
/// and a "Get Started" button that advances to the sign-in screen.
struct WelcomeView: View {
    let onGetStarted: () -> Void

    @State private var currentPage = 0

    private let cards: [(icon: String, title: String, description: String)] = [
        (
            "headphones.circle.fill",
            "Discover Stories",
            "Discover audio stories pinned to the world around you"
        ),
        (
            "mic.circle.fill",
            "Record & Share",
            "Record your own and share with the community"
        ),
        (
            "shield.checkered",
            "Safe Community",
            "Every story is reviewed to keep things safe"
        ),
    ]

    var body: some View {
        VStack(spacing: Theme.spacingLG) {
            Spacer()

            // App branding
            VStack(spacing: Theme.spacingSM) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)

                Text("Hear Here")
                    .font(.largeTitle.weight(.bold))

                Text("Stories live here")
                    .font(.title3)
                    .foregroundStyle(Theme.secondary)
            }

            Spacer()
                .frame(height: Theme.spacingMD)

            // Feature carousel
            TabView(selection: $currentPage) {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    featureCard(icon: card.icon, title: card.title, description: card.description)
                        .tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            #endif
            .frame(height: 180)
            .accessibilityElement(children: .contain)

            Spacer()

            // Get Started button
            Button("Get Started") {
                onGetStarted()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Theme.spacingLG)
            .accessibilityHint("Proceeds to the sign-in screen")

            Spacer()
                .frame(height: Theme.spacingXL)
        }
    }

    private func featureCard(icon: String, title: String, description: String) -> some View {
        VStack(spacing: Theme.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)

            Text(description)
                .font(.body)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacingXL)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Welcome") {
    WelcomeView {}
}

#Preview("Dark Mode") {
    WelcomeView {}
        .preferredColorScheme(.dark)
}
