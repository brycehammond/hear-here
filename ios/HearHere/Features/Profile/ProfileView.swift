import SwiftUI

/// The user's profile screen showing avatar, display name, email, and recordings list.
struct ProfileView: View {
    @Bindable var viewModel: ProfileViewModel
    @Bindable var coordinator: ProfileCoordinator

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            ScrollView {
                VStack(spacing: 24) {
                    profileHeader
                    recordingsSection
                }
                .padding()
            }
            .navigationTitle("Profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        coordinator.showSettings()
                    } label: {
                        Image(systemName: "gearshape")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens the settings screen")
                }
                #else
                ToolbarItem {
                    Button {
                        coordinator.showSettings()
                    } label: {
                        Image(systemName: "gearshape")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens the settings screen")
                }
                #endif
            }
            .navigationDestination(for: ProfileCoordinator.Destination.self) { destination in
                switch destination {
                case .recordingDetail(let recording):
                    RecordingDetailView(recording: recording, viewModel: viewModel)
                case .settings:
                    SettingsView(viewModel: SettingsViewModel(
                        apiClient: .preview,
                        authService: PreviewProfileAuthService(),
                        userEmail: viewModel.user?.email ?? ""
                    ))
                case .playback(let recording):
                    PlaybackView(viewModel: PlaybackViewModel(
                        recording: recording,
                        apiClient: .preview,
                        audioPlayer: PreviewProfilePlayer()
                    ))
                }
            }
            .refreshable {
                await viewModel.loadProfile()
                await viewModel.loadRecordings()
            }
            .task {
                if viewModel.user == nil {
                    await viewModel.loadProfile()
                }
                if viewModel.recordings.isEmpty {
                    await viewModel.loadRecordings()
                }
            }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 16) {
            if viewModel.isLoadingProfile && viewModel.user == nil {
                ProgressView()
                    .frame(height: 120)
            } else if let error = viewModel.profileError, viewModel.user == nil {
                profileErrorView(error: error)
            } else if let user = viewModel.user {
                userInfoView(user: user)
            }
        }
    }

    private func userInfoView(user: User) -> some View {
        VStack(spacing: 12) {
            // Avatar
            Image(systemName: "person.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            // Display Name
            if viewModel.isEditingDisplayName {
                HStack {
                    TextField("Display Name", text: $viewModel.editedDisplayName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Edit display name")

                    if viewModel.isSavingDisplayName {
                        ProgressView()
                    } else {
                        Button {
                            Task {
                                await viewModel.saveDisplayName()
                            }
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Save display name")

                        Button {
                            viewModel.cancelEditingDisplayName()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Cancel editing")
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Text(user.displayName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .accessibilityLabel("Display name: \(user.displayName)")

                    Button {
                        viewModel.startEditingDisplayName()
                    } label: {
                        Image(systemName: "pencil.circle")
                            .foregroundStyle(Color.accentColor)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Edit display name")
                    .accessibilityHint("Allows you to change your display name")
                }
            }

            Text(user.email)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Email: \(user.email)")

            Text("\(user.recordingCount) recording\(user.recordingCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("\(user.recordingCount) recordings")
        }
    }

    private func profileErrorView(error: Error) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("Could not load profile")
                .font(.subheadline)
                .fontWeight(.medium)

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task {
                    await viewModel.loadProfile()
                }
            }
            .frame(minHeight: 44)
            .accessibilityLabel("Retry loading profile")
        }
        .padding()
    }

    // MARK: - Recordings Section

    private var recordingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("My Recordings")
                    .font(.headline)

                if let user = viewModel.user {
                    Text("\(user.recordingCount)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                        .accessibilityLabel("\(user.recordingCount) total recordings")
                }

                Spacer()
            }

            MyRecordingsListView(viewModel: viewModel, coordinator: coordinator)
        }
    }
}

// MARK: - Preview Helpers

private final class PreviewProfileAuthService: AuthServiceProtocol, @unchecked Sendable {
    var state: AuthState = .signedOut
    func signInWithApple(authorization: ASAuthorization) async throws -> User { fatalError() }
    func signInWithGoogle() async throws -> User { fatalError() }
    func signInWithEmail(email: String, password: String) async throws -> User { fatalError() }
    func startSignUp(email: String, password: String) async throws -> SignUpCodeInfo { fatalError() }
    func submitSignUpCode(_ code: String) async throws -> User { fatalError() }
    func resendSignUpCode() async throws -> SignUpCodeInfo { fatalError() }
    func signInInteractively() async throws -> User { fatalError() }
    func signOut() throws {}
    func restoreSession() async {}
}

private final class PreviewProfilePlayer: AudioPlayerProtocol, @unchecked Sendable {
    var state: PlaybackState = .idle
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var progress: Double = 0
    func play(url: URL) {}
    func pause() {}
    func resume() {}
    func seek(to time: TimeInterval) async {}
    func stop() {}
}

import AuthenticationServices

// MARK: - Previews

#Preview("Populated") {
    ProfileView(
        viewModel: {
            let vm = ProfileViewModel(apiClient: .preview)
            vm.user = User(
                id: UUID(),
                displayName: "Jane Explorer",
                email: "jane@example.com",
                recordingCount: 12,
                createdAt: Date().addingTimeInterval(-86400 * 30)
            )
            vm.recordings = [
                Recording(
                    id: UUID(), userId: UUID(),
                    subject: "Morning at the market",
                    description: "The sounds of vendors setting up.",
                    latitude: 37.78, longitude: -122.41,
                    durationSeconds: 180, status: .approved,
                    createdAt: Date().addingTimeInterval(-3600)
                ),
                Recording(
                    id: UUID(), userId: UUID(),
                    subject: "Ocean waves at sunset",
                    description: nil,
                    latitude: 37.77, longitude: -122.51,
                    durationSeconds: 240, status: .pendingModeration,
                    createdAt: Date().addingTimeInterval(-7200)
                ),
                Recording(
                    id: UUID(), userId: UUID(),
                    subject: "Jazz in the park",
                    description: "A wonderful impromptu performance.",
                    latitude: 37.77, longitude: -122.45,
                    durationSeconds: 120, status: .rejected,
                    createdAt: Date().addingTimeInterval(-86400)
                ),
            ]
            return vm
        }(),
        coordinator: ProfileCoordinator()
    )
}

#Preview("Loading") {
    ProfileView(
        viewModel: {
            let vm = ProfileViewModel(apiClient: .preview)
            vm.isLoadingProfile = true
            return vm
        }(),
        coordinator: ProfileCoordinator()
    )
}

#Preview("Error") {
    ProfileView(
        viewModel: {
            let vm = ProfileViewModel(apiClient: .preview)
            vm.profileError = APIError.networkUnavailable
            return vm
        }(),
        coordinator: ProfileCoordinator()
    )
}
