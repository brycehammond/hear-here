import Observation
import SwiftUI

/// Manages the navigation path for the authentication flow.
///
/// Controls the onboarding flow from Welcome -> SignIn, keeping
/// navigation logic out of views.
@Observable
@MainActor
final class AuthCoordinator {
    /// Destinations within the auth flow.
    enum Destination: Hashable {
        case signIn
    }

    /// The navigation path for the auth flow.
    var path = NavigationPath()

    /// Navigates to the sign-in screen.
    func showSignIn() {
        path.append(Destination.signIn)
    }

    /// Pops back to the welcome screen.
    func popToRoot() {
        path.removeLast(path.count)
    }
}
