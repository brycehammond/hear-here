import AuthenticationServices
import Foundation
import MSAL
import Observation

/// The authentication state of the current user session.
///
/// Drives the top-level navigation gate in ``AppCoordinator``.
enum AuthState: Sendable {
    /// The auth session is being restored (e.g., on app launch).
    case loading

    /// No user is signed in.
    case signedOut

    /// A user is authenticated and their profile is available.
    case signedIn(User)
}

/// Protocol defining the authentication service interface.
///
/// Enables mock injection for testing and previews without MSAL dependency.
protocol AuthServiceProtocol: Sendable {
    /// The current authentication state.
    var state: AuthState { get }

    /// Signs in using Apple credentials from `ASAuthorization`.
    /// - Parameter authorization: The Apple sign-in authorization result.
    /// - Returns: The authenticated ``User``.
    func signInWithApple(authorization: ASAuthorization) async throws -> User

    /// Signs in interactively using B2C's hosted login UI.
    /// B2C handles identity provider selection (Google, email, etc.).
    /// - Returns: The authenticated ``User``.
    func signInInteractively() async throws -> User

    /// Signs out the current user and clears the local session.
    func signOut() throws

    /// Restores the previous session on app launch, if one exists.
    func restoreSession() async
}

/// Wraps MSAL to expose a clean observable authentication interface.
///
/// Handles Sign in with Apple, interactive B2C sign-in, session restoration,
/// and token management. The ``state`` property drives the app's auth gate.
@Observable
final class AuthService: @unchecked Sendable, AuthServiceProtocol, TokenProviding {
    private(set) var state: AuthState = .loading

    @ObservationIgnored
    private let msalApplication: MSALPublicClientApplication

    @ObservationIgnored
    private let scopes: [String]

    @ObservationIgnored
    private let appleAuthorityURL: URL?

    /// Creates an auth service backed by Azure AD B2C via MSAL.
    ///
    /// Configuration is read from the app's Info.plist (populated by xcconfig):
    /// - `B2C_TENANT_NAME`: The B2C tenant name (e.g., `hearhere-dev`)
    /// - `B2C_CLIENT_ID`: The app registration client ID
    /// - `B2C_POLICY_SIGNIN`: The sign-in user flow name (e.g., `B2C_1_signin`)
    /// - `B2C_REDIRECT_URI`: The redirect URI (e.g., `msauth.app.hearhere.dev://auth`)
    init() {
        let bundle = Bundle.main
        let tenantName = bundle.object(forInfoDictionaryKey: "B2C_TENANT_NAME") as? String ?? ""
        let clientId = bundle.object(forInfoDictionaryKey: "B2C_CLIENT_ID") as? String ?? ""
        let policySignIn = bundle.object(forInfoDictionaryKey: "B2C_POLICY_SIGNIN") as? String ?? ""
        let redirectURI = bundle.object(forInfoDictionaryKey: "B2C_REDIRECT_URI") as? String ?? ""

        let authorityURLString = "https://\(tenantName).b2clogin.com/\(tenantName).onmicrosoft.com/\(policySignIn)"

        // Build the Apple-specific authority URL for B2C Apple identity provider policy
        let applePolicyName = "\(policySignIn)_apple"
        let appleAuthorityURLString = "https://\(tenantName).b2clogin.com/\(tenantName).onmicrosoft.com/\(applePolicyName)"
        self.appleAuthorityURL = URL(string: appleAuthorityURLString)

        self.scopes = ["\(clientId)/.default"]

        do {
            guard let authorityURL = URL(string: authorityURLString) else {
                fatalError("Invalid B2C authority URL: \(authorityURLString)")
            }

            let b2cAuthority = try MSALB2CAuthority(url: authorityURL)

            let config = MSALPublicClientApplicationConfig(
                clientId: clientId,
                redirectUri: redirectURI,
                authority: b2cAuthority
            )
            config.knownAuthorities = [b2cAuthority]

            self.msalApplication = try MSALPublicClientApplication(configuration: config)
        } catch {
            fatalError("Failed to configure MSAL: \(error.localizedDescription)")
        }
    }

    /// Creates an auth service with a pre-configured MSAL application (for testing).
    init(msalApplication: MSALPublicClientApplication, scopes: [String]) {
        self.msalApplication = msalApplication
        self.scopes = scopes
        self.appleAuthorityURL = nil
    }

    func signInWithApple(authorization: ASAuthorization) async throws -> User {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = appleCredential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw APIError.unauthorized
        }

        // Use the Apple ID token as a login hint with B2C's Apple identity provider
        let parameters = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webViewParameters())

        if let appleAuthority = appleAuthorityURL {
            parameters.authority = try? MSALB2CAuthority(url: appleAuthority)
        }

        parameters.loginHint = tokenString
        parameters.promptType = .login

        let result = try await msalApplication.acquireToken(with: parameters)
        let user = mapMSALResult(result)
        state = .signedIn(user)
        return user
    }

    func signInInteractively() async throws -> User {
        let parameters = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webViewParameters())
        let result = try await msalApplication.acquireToken(with: parameters)
        let user = mapMSALResult(result)
        state = .signedIn(user)
        return user
    }

    func signOut() throws {
        guard let account = try? msalApplication.allAccounts().first else {
            state = .signedOut
            return
        }

        let parameters = MSALSignoutParameters(webviewParameters: webViewParameters())
        parameters.signoutFromBrowser = false

        msalApplication.signout(with: account, signoutParameters: parameters, completionBlock: { _, _ in })
        state = .signedOut
    }

    func restoreSession() async {
        do {
            guard let account = try msalApplication.allAccounts().first else {
                state = .signedOut
                return
            }

            let parameters = MSALSilentTokenParameters(scopes: scopes, account: account)
            let result = try await msalApplication.acquireTokenSilent(with: parameters)
            let user = mapMSALResult(result)
            state = .signedIn(user)
        } catch {
            state = .signedOut
        }
    }

    // MARK: - TokenProviding

    func currentToken() async throws -> String {
        guard let account = try msalApplication.allAccounts().first else {
            throw APIError.unauthorized
        }

        let parameters = MSALSilentTokenParameters(scopes: scopes, account: account)
        let result = try await msalApplication.acquireTokenSilent(with: parameters)
        return result.accessToken
    }

    func refreshToken() async throws -> String {
        guard let account = try msalApplication.allAccounts().first else {
            throw APIError.unauthorized
        }

        let parameters = MSALSilentTokenParameters(scopes: scopes, account: account)
        parameters.forceRefresh = true
        let result = try await msalApplication.acquireTokenSilent(with: parameters)
        return result.accessToken
    }

    // MARK: - Private

    private func webViewParameters() -> MSALWebviewParameters {
        #if canImport(UIKit)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first {
            return MSALWebviewParameters(authPresentationViewController: window.rootViewController!)
        }
        return MSALWebviewParameters()
        #else
        return MSALWebviewParameters()
        #endif
    }

    private func mapMSALResult(_ result: MSALResult) -> User {
        let claims = result.account.accountClaims ?? [:]
        let oid = claims["oid"] as? String ?? result.account.identifier ?? UUID().uuidString

        return User(
            id: UUID(uuidString: oid) ?? UUID(),
            displayName: claims["name"] as? String ?? "Anonymous",
            email: claims["emails"] as? String
                ?? (claims["emails"] as? [String])?.first
                ?? "",
            recordingCount: 0,
            createdAt: Date()
        )
    }
}
