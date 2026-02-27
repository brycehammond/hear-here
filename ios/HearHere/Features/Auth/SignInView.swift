import AuthenticationServices
import SwiftUI

/// Sign-in screen with Apple and B2C interactive authentication options.
///
/// Provides Sign in with Apple (required for App Store) and a general
/// sign-in button (B2C hosted UI), along with a terms/privacy footer
/// with tappable links.
struct SignInView: View {
    @Bindable var viewModel: AuthViewModel

    var body: some View {
        VStack(spacing: Theme.spacingLG) {
            Spacer()

            // Header
            VStack(spacing: Theme.spacingSM) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)

                Text("Sign In")
                    .font(.title.weight(.bold))

                Text("Choose how you'd like to sign in")
                    .font(.body)
                    .foregroundStyle(Theme.secondary)
            }

            Spacer()

            // Sign-in buttons
            VStack(spacing: Theme.spacingMD) {
                // Sign in with Apple
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task {
                        await viewModel.handleAppleSignIn(result: result)
                    }
                }
                .signInWithAppleButtonStyle(.whiteOutline)
                .frame(minHeight: Theme.minTapTarget)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
                .accessibilityLabel("Sign in with Apple")

                // Continue with email / other providers (B2C hosted UI)
                Button {
                    Task {
                        await viewModel.signIn()
                    }
                } label: {
                    HStack(spacing: Theme.spacingSM) {
                        Image(systemName: "person.circle.fill")
                            .font(.title3)
                        Text("Continue with Email")
                            .font(.body.weight(.semibold))
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Continue with email")

                // Error display
                if let error = viewModel.error {
                    ErrorView(message: error) {
                        viewModel.clearError()
                    }
                    .transition(.opacity)
                }

                // Loading indicator
                if viewModel.isLoading {
                    ProgressView("Signing in...")
                        .padding(.top, Theme.spacingSM)
                }
            }
            .padding(.horizontal, Theme.spacingLG)
            .disabled(viewModel.isLoading)

            Spacer()

            // Terms footer
            termsFooter
                .padding(.horizontal, Theme.spacingLG)
                .padding(.bottom, Theme.spacingLG)
        }
        .animation(.easeInOut, value: viewModel.error != nil)
    }

    private var termsFooter: some View {
        Text("By continuing, you agree to our [\(Text("Terms of Service").foregroundStyle(Theme.accent))](https://hearhere.app/terms) and [\(Text("Privacy Policy").foregroundStyle(Theme.accent))](https://hearhere.app/privacy)")
            .font(.caption)
            .foregroundStyle(Theme.secondary)
            .multilineTextAlignment(.center)
            .tint(Theme.accent)
    }
}

// MARK: - Previews

#Preview("Sign In") {
    let viewModel = AuthViewModel(
        authService: PreviewAuthService(),
        apiClient: APIClientKey.defaultValue,
        appCoordinator: AppCoordinator(authService: PreviewAuthService())
    )
    SignInView(viewModel: viewModel)
}

#Preview("Loading") {
    let viewModel = AuthViewModel(
        authService: PreviewAuthService(),
        apiClient: APIClientKey.defaultValue,
        appCoordinator: AppCoordinator(authService: PreviewAuthService())
    )
    SignInView(viewModel: viewModel)
        .onAppear { viewModel.isLoading = true }
}

#Preview("Error") {
    let viewModel = AuthViewModel(
        authService: PreviewAuthService(),
        apiClient: APIClientKey.defaultValue,
        appCoordinator: AppCoordinator(authService: PreviewAuthService())
    )
    SignInView(viewModel: viewModel)
        .onAppear { viewModel.error = "Authentication failed. Please try again." }
}
