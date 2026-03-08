import SwiftUI

/// Container NavigationStack for the onboarding flow: Welcome -> SignIn.
///
/// Manages the auth flow navigation path and creates the view model
/// for the sign-in screen.
struct OnboardingView: View {
    @State private var authCoordinator = AuthCoordinator()
    @State private var emailAuthViewModel: EmailAuthViewModel?
    @Environment(\.authService) private var authService
    @Environment(\.apiClient) private var apiClient

    let coordinator: AppCoordinator

    var body: some View {
        NavigationStack(path: $authCoordinator.path) {
            WelcomeView {
                authCoordinator.showSignIn()
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .navigationDestination(for: AuthCoordinator.Destination.self) { destination in
                switch destination {
                case .signIn:
                    SignInView(
                        viewModel: AuthViewModel(
                            authService: authService,
                            apiClient: apiClient,
                            appCoordinator: coordinator
                        ),
                        onEmailSignIn: { authCoordinator.showEmailSignIn() }
                    )
                    .navigationBarBackButtonHidden(false)
                    .navigationTitle("")

                case .emailSignIn:
                    EmailSignInView(
                        viewModel: resolveEmailAuthViewModel(),
                        onCreateAccount: { authCoordinator.showEmailSignUp() }
                    )
                    .navigationTitle("")

                case .emailSignUp:
                    EmailSignUpView(viewModel: resolveEmailAuthViewModel())
                        .navigationTitle("")
                        .onChange(of: resolveEmailAuthViewModel().needsVerification) { _, needsVerification in
                            if needsVerification {
                                authCoordinator.showVerifyCode()
                            }
                        }

                case .verifyCode:
                    VerifyCodeView(viewModel: resolveEmailAuthViewModel())
                        .navigationTitle("")
                }
            }
        }
    }

    private func resolveEmailAuthViewModel() -> EmailAuthViewModel {
        if let existing = emailAuthViewModel {
            return existing
        }
        let vm = EmailAuthViewModel(
            authService: authService,
            apiClient: apiClient,
            appCoordinator: coordinator
        )
        emailAuthViewModel = vm
        return vm
    }
}

// MARK: - Previews

#Preview("Onboarding Flow") {
    OnboardingView(coordinator: AppCoordinator(authService: PreviewAuthService()))
}

#Preview("Sign In") {
    OnboardingView(coordinator: AppCoordinator(authService: PreviewAuthService()))
}
