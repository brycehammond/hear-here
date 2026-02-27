import AuthenticationServices
import SwiftUI

/// Settings screen with account info, notifications, about section, and account deletion.
///
/// Account deletion uses a two-step confirmation flow to prevent accidental deletion:
/// first alert asks "Are you sure?", second alert asks "This cannot be undone."
struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        List {
            accountSection
            notificationsSection
            aboutSection
            dangerZoneSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.checkNotificationStatus()
        }
        // First deletion confirmation
        .alert("Delete Account?", isPresented: $viewModel.showFirstDeleteConfirmation) {
            Button("Continue", role: .destructive) {
                viewModel.confirmFirstDeletion()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDeletion()
            }
        } message: {
            Text("This will permanently delete your account and all your recordings. This action cannot be undone.")
        }
        // Second deletion confirmation
        .alert("Are you absolutely sure?", isPresented: $viewModel.showSecondDeleteConfirmation) {
            Button("Delete My Account", role: .destructive) {
                Task {
                    await viewModel.confirmSecondDeletion()
                }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDeletion()
            }
        } message: {
            Text("All your recordings will be permanently removed. You will be signed out and cannot recover your account.")
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        Section("Account") {
            if !viewModel.userEmail.isEmpty {
                HStack {
                    Text("Email")
                        .accessibilityLabel("Email")
                    Spacer()
                    Text(viewModel.userEmail)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Email: \(viewModel.userEmail)")
                }
                .frame(minHeight: 44)
            }

            Button(role: .destructive) {
                viewModel.signOut()
            } label: {
                HStack {
                    Text("Sign Out")
                    Spacer()
                    if viewModel.isSigningOut {
                        ProgressView()
                    }
                }
                .frame(minHeight: 44)
            }
            .disabled(viewModel.isSigningOut)
            .accessibilityLabel("Sign out")
            .accessibilityHint("Signs you out of your account")

            if let error = viewModel.signOutError {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle(isOn: Binding(
                get: { viewModel.notificationsEnabled },
                set: { _ in
                    Task {
                        await viewModel.toggleNotifications()
                    }
                }
            )) {
                Text("Push Notifications")
            }
            .frame(minHeight: 44)
            .accessibilityLabel("Push notifications")
            .accessibilityHint("Get notified when your recordings are approved")
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(viewModel.appVersion)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .accessibilityLabel("App version \(viewModel.appVersion)")

            Link(destination: URL(string: "https://hearhere.app/terms")!) {
                HStack {
                    Text("Terms of Service")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Terms of Service")
            .accessibilityHint("Opens the terms of service in your browser")

            Link(destination: URL(string: "https://hearhere.app/privacy")!) {
                HStack {
                    Text("Privacy Policy")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Privacy Policy")
            .accessibilityHint("Opens the privacy policy in your browser")

            Link(destination: URL(string: "https://hearhere.app/licenses")!) {
                HStack {
                    Text("Open-Source Licenses")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Open-source licenses")
            .accessibilityHint("Opens the open-source license attributions")
        }
    }

    // MARK: - Danger Zone

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                viewModel.requestAccountDeletion()
            } label: {
                HStack {
                    Label("Delete Account", systemImage: "trash")
                    Spacer()
                    if viewModel.isDeletingAccount {
                        ProgressView()
                    }
                }
                .frame(minHeight: 44)
            }
            .disabled(viewModel.isDeletingAccount)
            .accessibilityLabel("Delete account")
            .accessibilityHint("Permanently deletes your account and all recordings")

            if let error = viewModel.deleteAccountError {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } footer: {
            Text("Deleting your account is permanent and cannot be undone.")
                .font(.caption)
        }
    }

}

// MARK: - Previews

#Preview("Settings") {
    NavigationStack {
        SettingsView(
            viewModel: SettingsViewModel(
                apiClient: .preview,
                authService: PreviewSettingsAuthService(),
                userEmail: "jane@example.com"
            )
        )
    }
}

private final class PreviewSettingsAuthService: AuthServiceProtocol, @unchecked Sendable {
    var state: AuthState = .signedIn(User(
        id: UUID(),
        displayName: "Jane Explorer",
        email: "jane@example.com",
        recordingCount: 12,
        createdAt: Date()
    ))
    func signInWithApple(authorization: ASAuthorization) async throws -> User { fatalError() }
    func signInInteractively() async throws -> User { fatalError() }
    func signOut() throws {}
    func restoreSession() async {}
}
