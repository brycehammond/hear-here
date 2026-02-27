import Foundation

/// Request body for registering a new user account.
///
/// Sent to `POST /v1/users/register` after successful authentication.
struct RegisterRequest: Codable, Sendable {
    let displayName: String
    let email: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case email
    }
}

/// User profile as returned by the API.
struct UserResponse: Codable, Sendable {
    let id: UUID
    let displayName: String
    let email: String
    let recordingCount: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case email
        case recordingCount = "recording_count"
        case createdAt = "created_at"
    }

    /// Converts this DTO to a domain ``User`` model.
    func toDomain() -> User {
        User(
            id: id,
            displayName: displayName,
            email: email,
            recordingCount: recordingCount,
            createdAt: createdAt
        )
    }
}

/// Request body for updating the current user's profile.
struct UpdateUserRequest: Codable, Sendable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}
