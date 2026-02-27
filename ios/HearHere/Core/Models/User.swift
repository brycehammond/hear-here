import Foundation

/// Domain model representing an authenticated user of the Hear Here app.
///
/// This is the client-side representation of a user, distinct from the
/// ``UserDTO`` types used for API communication. The model contains
/// only the information needed for display and local state management.
struct User: Identifiable, Hashable, Sendable {
    /// The unique server-assigned identifier for this user.
    let id: UUID

    /// The user's chosen display name shown on their recordings and profile.
    var displayName: String

    /// The user's email address from their authentication provider.
    let email: String

    /// The total number of recordings this user has created.
    var recordingCount: Int

    /// The date and time when the user account was created.
    let createdAt: Date
}
