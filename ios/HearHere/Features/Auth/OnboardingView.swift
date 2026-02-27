import SwiftUI

/// Container NavigationStack for the onboarding flow: Welcome -> SignIn.
///
/// Manages the auth flow navigation path and creates the view model
/// for the sign-in screen.
struct OnboardingView: View {
    @State private var authCoordinator = AuthCoordinator()
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
                        )
                    )
                    .navigationBarBackButtonHidden(false)
                    .navigationTitle("")
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Onboarding Flow") {
    OnboardingView(coordinator: AppCoordinator(authService: PreviewAuthService()))
}
