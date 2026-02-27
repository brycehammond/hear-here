import Observation
import SwiftUI

/// Root navigation coordinator managing the auth gate and tab selection.
///
/// Observes the ``AuthServiceProtocol`` to transition between authentication
/// states (loading, onboarding, authenticated) and tracks the currently
/// selected tab.
@Observable
@MainActor
final class AppCoordinator {

    /// The top-level auth gate state determining which root view is shown.
    enum AuthGate: Sendable {
        /// Restoring the user session on app launch.
        case loading
        /// No active session; show the onboarding/sign-in flow.
        case onboarding
        /// User is authenticated; show the main tab view.
        case authenticated
    }

    /// The available tabs in the main tab view.
    enum Tab: Hashable, Sendable {
        case discover
        case record
        case profile
    }

    /// The current auth gate state.
    var authState: AuthGate = .loading

    /// The currently selected tab.
    var tabSelection: Tab = .discover

    private let authService: any AuthServiceProtocol

    /// Creates an app coordinator that observes the given auth service.
    /// - Parameter authService: The auth service to observe for session changes.
    init(authService: any AuthServiceProtocol) {
        self.authService = authService
    }

    /// Restores the user session on app launch and transitions the auth gate accordingly.
    func restoreSession() async {
        await authService.restoreSession()
        updateAuthGate(from: authService.state)
    }

    /// Updates the auth gate based on the current auth state.
    ///
    /// Call this when the auth service state changes (e.g., after sign-in or sign-out).
    func updateAuthGate(from state: AuthState) {
        switch state {
        case .loading:
            authState = .loading
        case .signedOut:
            authState = .onboarding
        case .signedIn:
            authState = .authenticated
        }
    }

    /// Signs the user out and returns to the onboarding flow.
    func signOut() throws {
        try authService.signOut()
        authState = .onboarding
        tabSelection = .discover
    }
}
