import Observation
import SwiftUI

/// Manages the native email/password sign-in and sign-up flows.
///
/// Handles the multi-step sign-up flow (email+password → OTP verification → sign-in)
/// and the single-step sign-in flow (email+password → done).
@Observable
@MainActor
final class EmailAuthViewModel {
    var email = ""
    var password = ""
    var displayName = ""
    var verificationCode = ""
    var isLoading = false
    var error: String?

    /// Info about the verification code sent during sign-up.
    var codeInfo: SignUpCodeInfo?

    /// Whether sign-up has reached the OTP verification step.
    var needsVerification = false

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

    // MARK: - Sign In

    func signIn() async {
        guard validateEmail(), validatePassword() else { return }

        isLoading = true
        error = nil

        do {
            let user = try await authService.signInWithEmail(email: email, password: password)
            try await registerWithBackend(user: user)
            appCoordinator.updateAuthGate(from: authService.state)
        } catch {
            self.error = mapError(error)
        }

        isLoading = false
    }

    // MARK: - Sign Up

    func signUp() async {
        guard validateEmail(), validatePassword(), validateDisplayName() else { return }

        isLoading = true
        error = nil

        do {
            let info = try await authService.startSignUp(email: email, password: password)
            codeInfo = info
            needsVerification = true
        } catch {
            self.error = mapError(error)
        }

        isLoading = false
    }

    func submitCode() async {
        let code = verificationCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else {
            error = "Please enter the verification code."
            return
        }

        isLoading = true
        error = nil

        do {
            let user = try await authService.submitSignUpCode(code)
            try await registerWithBackend(user: user)
            appCoordinator.updateAuthGate(from: authService.state)
        } catch {
            self.error = mapError(error)
        }

        isLoading = false
    }

    func resendCode() async {
        isLoading = true
        error = nil

        do {
            codeInfo = try await authService.resendSignUpCode()
        } catch {
            self.error = mapError(error)
        }

        isLoading = false
    }

    func clearError() {
        error = nil
    }

    // MARK: - Private

    private func validateEmail() -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || !trimmed.contains("@") {
            error = "Please enter a valid email address."
            return false
        }
        return true
    }

    private func validatePassword() -> Bool {
        if password.count < 8 {
            error = "Password must be at least 8 characters."
            return false
        }
        return true
    }

    private func validateDisplayName() -> Bool {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            error = "Please enter a display name."
            return false
        }
        return true
    }

    private func registerWithBackend(user: User) async throws {
        let request = RegisterRequest(displayName: displayName.isEmpty ? user.displayName : displayName, email: user.email)
        _ = try await apiClient.request(.register(request), type: UserResponse.self)
    }

    private func mapError(_ error: Error) -> String {
        error.localizedDescription
    }
}
