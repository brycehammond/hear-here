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

/// Info about a sign-up verification code that was sent to the user.
struct SignUpCodeInfo: Sendable {
    let sentTo: String
    let codeLength: Int
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

    /// Signs in with Google via B2C's federated Google identity provider.
    /// Uses `domain_hint` to bypass B2C's provider selection page.
    /// - Returns: The authenticated ``User``.
    func signInWithGoogle() async throws -> User

    /// Signs in natively with email and password (no webview).
    /// - Returns: The authenticated ``User``.
    func signInWithEmail(email: String, password: String) async throws -> User

    /// Starts a native sign-up flow with email and password.
    /// An OTP verification code is sent to the email address.
    /// - Returns: Info about the verification code that was sent.
    func startSignUp(email: String, password: String) async throws -> SignUpCodeInfo

    /// Submits the OTP verification code during sign-up, then auto-signs-in.
    /// - Returns: The authenticated ``User``.
    func submitSignUpCode(_ code: String) async throws -> User

    /// Resends the sign-up OTP verification code.
    /// - Returns: Updated info about the new verification code.
    func resendSignUpCode() async throws -> SignUpCodeInfo

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

    @ObservationIgnored
    private let nativeAuthClient: MSALNativeAuthPublicClientApplication?

    /// Stores the in-progress sign-up state between code-required and code-submit steps.
    @ObservationIgnored
    private var signUpCodeState: MSAL.SignUpCodeRequiredState?

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

        // Native auth client for email/password sign-in and sign-up (no webview)
        do {
            self.nativeAuthClient = try MSALNativeAuthPublicClientApplication(
                clientId: clientId,
                tenantSubdomain: tenantName,
                challengeTypes: [.OOB, .password]
            )
        } catch {
            print("Native auth not available: \(error.localizedDescription)")
            self.nativeAuthClient = nil
        }
    }

    /// Creates an auth service with a pre-configured MSAL application (for testing).
    init(msalApplication: MSALPublicClientApplication, scopes: [String]) {
        self.msalApplication = msalApplication
        self.scopes = scopes
        self.appleAuthorityURL = nil
        self.nativeAuthClient = nil
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

    func signInWithGoogle() async throws -> User {
        let parameters = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webViewParameters())
        parameters.extraQueryParameters = ["domain_hint": "google.com"]
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

    // MARK: - Native Email/Password Authentication

    func signInWithEmail(email: String, password: String) async throws -> User {
        guard let nativeAuth = nativeAuthClient else {
            throw APIError.unauthorized
        }

        return try await withCheckedThrowingContinuation { continuation in
            let params = MSALNativeAuthSignInParameters(username: email)
            params.password = password
            nativeAuth.signIn(parameters: params, delegate: NativeSignInDelegate(continuation: continuation, mapResult: { [weak self] result in
                let accessTokenParams = MSALNativeAuthGetAccessTokenParameters()
                result.getAccessToken(parameters: accessTokenParams, delegate: NativeCredentialsDelegate(continuation: continuation, onToken: { [weak self] tokenResult in
                    let user = self?.mapNativeAuthResult(result, accessToken: tokenResult.accessToken) ?? User(id: UUID(), displayName: "User", email: email, recordingCount: 0, createdAt: Date())
                    self?.state = .signedIn(user)
                    continuation.resume(returning: user)
                }))
            }))
        }
    }

    func startSignUp(email: String, password: String) async throws -> SignUpCodeInfo {
        guard let nativeAuth = nativeAuthClient else {
            throw APIError.unauthorized
        }

        return try await withCheckedThrowingContinuation { continuation in
            let params = MSALNativeAuthSignUpParameters(username: email)
            params.password = password
            nativeAuth.signUp(parameters: params, delegate: NativeSignUpStartDelegate(continuation: continuation, onCodeRequired: { [weak self] state, sentTo, codeLength in
                self?.signUpCodeState = state
                continuation.resume(returning: SignUpCodeInfo(sentTo: sentTo, codeLength: codeLength))
            }))
        }
    }

    func submitSignUpCode(_ code: String) async throws -> User {
        guard let codeState = signUpCodeState else {
            throw APIError.unauthorized
        }

        // Single continuation that chains: submit code → auto sign-in → get token
        return try await withCheckedThrowingContinuation { continuation in
            codeState.submitCode(code: code, delegate: NativeSignUpVerifyCodeDelegate(
                onError: { [weak self] error in
                    self?.signUpCodeState = nil
                    continuation.resume(throwing: error)
                },
                onCompleted: { [weak self] signInState in
                    self?.signUpCodeState = nil
                    signInState.signIn(delegate: NativeSignInAfterSignUpDelegate(
                        onError: { error in
                            continuation.resume(throwing: error)
                        },
                        onCompleted: { result in
                            let params = MSALNativeAuthGetAccessTokenParameters()
                            result.getAccessToken(parameters: params, delegate: NativeCredentialsDelegate(
                                continuation: continuation,
                                onToken: { [weak self] tokenResult in
                                    let user = self?.mapNativeAuthResult(result, accessToken: tokenResult.accessToken)
                                        ?? User(id: UUID(), displayName: "User", email: "", recordingCount: 0, createdAt: Date())
                                    self?.state = .signedIn(user)
                                    continuation.resume(returning: user)
                                }
                            ))
                        }
                    ))
                }
            ))
        }
    }

    func resendSignUpCode() async throws -> SignUpCodeInfo {
        guard let codeState = signUpCodeState else {
            throw APIError.unauthorized
        }

        return try await withCheckedThrowingContinuation { continuation in
            codeState.resendCode(delegate: NativeResendCodeDelegate(continuation: continuation, onCodeRequired: { [weak self] newState, sentTo, codeLength in
                self?.signUpCodeState = newState
                continuation.resume(returning: SignUpCodeInfo(sentTo: sentTo, codeLength: codeLength))
            }))
        }
    }

    private func mapNativeAuthResult(_ result: MSALNativeAuthUserAccountResult, accessToken: String) -> User {
        let claims = result.account.accountClaims ?? [:]
        let oid = claims["oid"] as? String ?? result.account.identifier ?? UUID().uuidString

        return User(
            id: UUID(uuidString: oid) ?? UUID(),
            displayName: claims["name"] as? String ?? "User",
            email: claims["preferred_username"] as? String
                ?? claims["email"] as? String
                ?? "",
            recordingCount: 0,
            createdAt: Date()
        )
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

// MARK: - Native Auth Delegate Wrappers

/// Wraps `SignInStartDelegate` for email+password sign-in.
private final class NativeSignInDelegate: NSObject, SignInStartDelegate {
    let continuation: CheckedContinuation<User, Error>
    let mapResult: (MSALNativeAuthUserAccountResult) -> Void

    init(continuation: CheckedContinuation<User, Error>, mapResult: @escaping (MSALNativeAuthUserAccountResult) -> Void) {
        self.continuation = continuation
        self.mapResult = mapResult
    }

    func onSignInStartError(error: MSAL.SignInStartError) {
        continuation.resume(throwing: error)
    }

    func onSignInCompleted(result: MSAL.MSALNativeAuthUserAccountResult) {
        mapResult(result)
    }
}

/// Wraps `CredentialsDelegate` for access token retrieval.
private final class NativeCredentialsDelegate: NSObject, CredentialsDelegate {
    let continuation: CheckedContinuation<User, Error>
    let onToken: (MSALNativeAuthTokenResult) -> Void

    init(continuation: CheckedContinuation<User, Error>, onToken: @escaping (MSALNativeAuthTokenResult) -> Void) {
        self.continuation = continuation
        self.onToken = onToken
    }

    func onAccessTokenRetrieveError(error: MSAL.RetrieveAccessTokenError) {
        continuation.resume(throwing: error)
    }

    func onAccessTokenRetrieveCompleted(result: MSALNativeAuthTokenResult) {
        onToken(result)
    }
}

/// Wraps `SignUpStartDelegate` for email+password sign-up.
private final class NativeSignUpStartDelegate: NSObject, SignUpStartDelegate {
    let continuation: CheckedContinuation<SignUpCodeInfo, Error>
    let onCodeRequired: (MSAL.SignUpCodeRequiredState, String, Int) -> Void

    init(continuation: CheckedContinuation<SignUpCodeInfo, Error>, onCodeRequired: @escaping (MSAL.SignUpCodeRequiredState, String, Int) -> Void) {
        self.continuation = continuation
        self.onCodeRequired = onCodeRequired
    }

    func onSignUpStartError(error: MSAL.SignUpStartError) {
        continuation.resume(throwing: error)
    }

    func onSignUpCodeRequired(
        newState: MSAL.SignUpCodeRequiredState,
        sentTo: String,
        channelTargetType: MSAL.MSALNativeAuthChannelType,
        codeLength: Int
    ) {
        onCodeRequired(newState, sentTo, codeLength)
    }
}

/// Wraps `SignUpVerifyCodeDelegate` using callbacks to chain the next step
/// without passing non-Sendable MSAL state through a continuation boundary.
private final class NativeSignUpVerifyCodeDelegate: NSObject, SignUpVerifyCodeDelegate {
    let onError: (Error) -> Void
    let onCompleted: (MSAL.SignInAfterSignUpState) -> Void

    init(onError: @escaping (Error) -> Void, onCompleted: @escaping (MSAL.SignInAfterSignUpState) -> Void) {
        self.onError = onError
        self.onCompleted = onCompleted
    }

    func onSignUpVerifyCodeError(error: MSAL.VerifyCodeError, newState: MSAL.SignUpCodeRequiredState?) {
        onError(error)
    }

    func onSignUpCompleted(newState: MSAL.SignInAfterSignUpState) {
        onCompleted(newState)
    }
}

/// Wraps `SignInAfterSignUpDelegate` using callbacks to chain token retrieval
/// without passing non-Sendable MSAL state through a continuation boundary.
private final class NativeSignInAfterSignUpDelegate: NSObject, SignInAfterSignUpDelegate {
    let onError: (Error) -> Void
    let onCompleted: (MSALNativeAuthUserAccountResult) -> Void

    init(onError: @escaping (Error) -> Void, onCompleted: @escaping (MSALNativeAuthUserAccountResult) -> Void) {
        self.onError = onError
        self.onCompleted = onCompleted
    }

    func onSignInAfterSignUpError(error: MSAL.SignInAfterSignUpError) {
        onError(error)
    }

    func onSignInCompleted(result: MSAL.MSALNativeAuthUserAccountResult) {
        onCompleted(result)
    }
}

/// Wraps `SignUpResendCodeDelegate` for resending verification codes.
private final class NativeResendCodeDelegate: NSObject, SignUpResendCodeDelegate {
    let continuation: CheckedContinuation<SignUpCodeInfo, Error>
    let onCodeRequired: (MSAL.SignUpCodeRequiredState, String, Int) -> Void

    init(continuation: CheckedContinuation<SignUpCodeInfo, Error>, onCodeRequired: @escaping (MSAL.SignUpCodeRequiredState, String, Int) -> Void) {
        self.continuation = continuation
        self.onCodeRequired = onCodeRequired
    }

    func onSignUpResendCodeError(error: MSAL.ResendCodeError, newState: MSAL.SignUpCodeRequiredState?) {
        continuation.resume(throwing: error)
    }

    func onSignUpResendCodeCodeRequired(
        newState: MSAL.SignUpCodeRequiredState,
        sentTo: String,
        channelTargetType: MSAL.MSALNativeAuthChannelType,
        codeLength: Int
    ) {
        onCodeRequired(newState, sentTo, codeLength)
    }
}
