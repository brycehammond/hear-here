import Foundation
import Observation

/// Filter options for the user's recordings list.
enum RecordingFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case published = "Published"
    case underReview = "Under Review"
    case notPublished = "Not Published"

    var id: String { rawValue }

    func matches(_ status: ModerationStatus) -> Bool {
        switch self {
        case .all:
            return true
        case .published:
            return status == .approved
        case .underReview:
            return status.isPending
        case .notPublished:
            return status == .rejected
        }
    }
}

/// Manages the user profile, recordings list, and related actions.
///
/// Loads the user profile and their recordings with cursor-based pagination.
/// Supports filtering by moderation status, display name editing, and recording deletion.
@Observable
@MainActor
final class ProfileViewModel {
    // MARK: - State

    var user: User?
    var recordings: [Recording] = []
    var isLoadingProfile = false
    var isLoadingRecordings = false
    var isLoadingMore = false
    var profileError: Error?
    var recordingsError: Error?
    var selectedFilter: RecordingFilter = .all
    var isEditingDisplayName = false
    var editedDisplayName = ""
    var isSavingDisplayName = false
    var deleteError: Error?
    var showDeleteConfirmation = false
    var recordingToDelete: Recording?

    var filteredRecordings: [Recording] {
        recordings.filter { selectedFilter.matches($0.status) }
    }

    var hasMoreRecordings: Bool {
        nextCursor != nil
    }

    // MARK: - Dependencies

    private let apiClient: APIClient
    private var nextCursor: String?

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Profile

    func loadProfile() async {
        isLoadingProfile = true
        profileError = nil

        do {
            let response = try await apiClient.request(.getMe, type: UserResponse.self)
            user = response.toDomain()
            isLoadingProfile = false
        } catch {
            profileError = error
            isLoadingProfile = false
        }
    }

    func startEditingDisplayName() {
        editedDisplayName = user?.displayName ?? ""
        isEditingDisplayName = true
    }

    func saveDisplayName() async {
        guard !editedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSavingDisplayName = true

        do {
            let request = UpdateUserRequest(displayName: editedDisplayName)
            let response = try await apiClient.request(.updateMe(request), type: UserResponse.self)
            user = response.toDomain()
            isEditingDisplayName = false
        } catch {
            profileError = error
        }
        isSavingDisplayName = false
    }

    func cancelEditingDisplayName() {
        isEditingDisplayName = false
        editedDisplayName = ""
    }

    // MARK: - Recordings

    func loadRecordings() async {
        isLoadingRecordings = true
        recordingsError = nil
        nextCursor = nil

        do {
            let response = try await apiClient.request(
                .myRecordings(cursor: nil, limit: 20),
                type: PaginatedResponse<RecordingResponse>.self
            )
            recordings = response.items.map { $0.toDomain() }
            nextCursor = response.nextCursor
            isLoadingRecordings = false
        } catch {
            recordingsError = error
            isLoadingRecordings = false
        }
    }

    func loadMoreRecordings() async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true

        do {
            let response = try await apiClient.request(
                .myRecordings(cursor: cursor, limit: 20),
                type: PaginatedResponse<RecordingResponse>.self
            )
            recordings.append(contentsOf: response.items.map { $0.toDomain() })
            nextCursor = response.nextCursor
        } catch {
            recordingsError = error
        }
        isLoadingMore = false
    }

    // MARK: - Deletion

    func confirmDelete(_ recording: Recording) {
        recordingToDelete = recording
        showDeleteConfirmation = true
    }

    func deleteRecording() async {
        guard let recording = recordingToDelete else { return }
        deleteError = nil

        do {
            try await apiClient.requestVoid(.deleteRecording(id: recording.id))
            recordings.removeAll { $0.id == recording.id }
            if var currentUser = user {
                currentUser.recordingCount = max(0, currentUser.recordingCount - 1)
                user = currentUser
            }
            recordingToDelete = nil
        } catch {
            deleteError = error
        }
    }

    func cancelDelete() {
        recordingToDelete = nil
        showDeleteConfirmation = false
    }
}
