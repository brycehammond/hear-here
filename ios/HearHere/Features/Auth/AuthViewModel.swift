import AuthenticationServices
import Observation
import SwiftUI

/// Handles sign-in operations and registration with the backend API.
///
/// Manages loading and error states for both Apple and interactive B2C sign-in flows.
/// On successful authentication, registers the user with the backend via
/// `POST /v1/users/register` and transitions the app coordinator to the
/// authenticated state.
@Observable
@MainActor
final class AuthViewModel {
    var isLoading = false
    var error: String?

    private let authService: any AuthServiceProtocol
    private let apiClient: APIClient
    private let appCoordinator: AppCoordinator

    init(
        authService: any AuthServiceProtocol,
        apiClient: APIClient,
        appCoordinator: AppCoordinator
    ) {
        self.authService = authService
        self.apiClient = apiClient
        self.appCoordinator = appCoordinator
    }

    /// Handles the result of an Apple Sign-In authorization request.
    func handleAppleSignIn(result: Result<ASAuthorization, Error>) async {
        isLoading = true
        error = nil

        do {
            switch result {
            case .success(let authorization):
                let user = try await authService.signInWithApple(authorization: authorization)
                try await registerWithBackend(user: user)
                appCoordinator.updateAuthGate(from: authService.state)
            case .failure(let authError):
                // User cancelled is not an error worth showing
                if (authError as NSError).code == ASAuthorizationError.canceled.rawValue {
                    isLoading = false
                    return
                }
                error = authError.localizedDescription
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    /// Initiates interactive B2C sign-in and registers with the backend.
    ///
    /// B2C's hosted login page handles identity provider selection
    /// (Google, email, etc.) — no need to manage the presenting window.
    func signIn() async {
        isLoading = true
        error = nil

        do {
            let user = try await authService.signInInteractively()
            try await registerWithBackend(user: user)
            appCoordinator.updateAuthGate(from: authService.state)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    /// Clears any displayed error.
    func clearError() {
        error = nil
    }

    // MARK: - Private

    private func registerWithBackend(user: User) async throws {
        let request = RegisterRequest(displayName: user.displayName, email: user.email)
        _ = try await apiClient.request(.register(request), type: UserResponse.self)
    }
}
