import SwiftUI

/// Inline error display with a message and optional retry button.
///
/// Designed for contextual display near the failed content area, not as a modal alert.
/// Provides VoiceOver accessibility with the error message and retry hint.
struct ErrorView: View {
    let message: String
    var retryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.spacingSM) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(Theme.error)
                .accessibilityHidden(true)

            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.onSurface)
                .multilineTextAlignment(.center)

            if let retryAction {
                Button("Retry") {
                    retryAction()
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(maxWidth: 200)
                .accessibilityHint("Attempts the failed operation again")
            }
        }
        .padding(Theme.spacingMD)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("With Retry") {
    ErrorView(
        message: "Something went wrong. Please try again.",
        retryAction: {}
    )
}

#Preview("Without Retry") {
    ErrorView(message: "The recording could not be found.")
}

#Preview("Long Message") {
    ErrorView(
        message: "No internet connection. Please check your Wi-Fi or cellular connection and try again.",
        retryAction: {}
    )
}
