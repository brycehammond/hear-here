import Foundation
import Observation
import UserNotifications

/// Manages settings state including notifications, sign out, and account deletion.
///
/// The account deletion flow requires two-step confirmation: the user must confirm
/// once in an alert, then confirm again in a second alert before the deletion
/// proceeds. This prevents accidental account loss.
@Observable
@MainActor
final class SettingsViewModel {
    // MARK: - State

    var notificationsEnabled = false
    var isCheckingNotifications = false
    var isSigningOut = false
    var signOutError: Error?

    // Account deletion flow
    var showFirstDeleteConfirmation = false
    var showSecondDeleteConfirmation = false
    var isDeletingAccount = false
    var deleteAccountError: Error?

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    /// The user's email address, displayed as read-only in the account section.
    let userEmail: String

    // MARK: - Dependencies

    private let apiClient: APIClient
    private let authService: any AuthServiceProtocol

    init(apiClient: APIClient, authService: any AuthServiceProtocol, userEmail: String = "") {
        self.apiClient = apiClient
        self.authService = authService
        self.userEmail = userEmail
    }

    // MARK: - Notifications

    func checkNotificationStatus() async {
        isCheckingNotifications = true
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsEnabled = settings.authorizationStatus == .authorized
        isCheckingNotifications = false
    }

    func toggleNotifications() async {
        if notificationsEnabled {
            // Direct user to settings to disable
            #if canImport(UIKit)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
            #endif
        } else {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
                notificationsEnabled = granted
            } catch {
                notificationsEnabled = false
            }
        }
    }

    // MARK: - Sign Out

    func signOut() {
        isSigningOut = true
        signOutError = nil

        do {
            try authService.signOut()
        } catch {
            signOutError = error
        }
        isSigningOut = false
    }

    // MARK: - Account Deletion

    func requestAccountDeletion() {
        showFirstDeleteConfirmation = true
    }

    func confirmFirstDeletion() {
        showFirstDeleteConfirmation = false
        showSecondDeleteConfirmation = true
    }

    func confirmSecondDeletion() async {
        isDeletingAccount = true
        deleteAccountError = nil
        showSecondDeleteConfirmation = false

        do {
            try await apiClient.requestVoid(.deleteAccount)
            try authService.signOut()
        } catch {
            deleteAccountError = error
        }
        isDeletingAccount = false
    }

    func cancelDeletion() {
        showFirstDeleteConfirmation = false
        showSecondDeleteConfirmation = false
    }
}
