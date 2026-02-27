import Foundation

/// Request body for creating a new recording.
///
/// Sent to `POST /v1/recordings` with the recording metadata.
/// The server responds with a pre-signed upload URL.
struct CreateRecordingRequest: Codable, Sendable {
    let subject: String
    let description: String?
    let latitude: Double
    let longitude: Double
    let durationSec: Double

    enum CodingKeys: String, CodingKey {
        case subject
        case description
        case latitude
        case longitude
        case durationSec = "duration_sec"
    }
}

/// Response from creating a recording, includes the pre-signed upload URL.
struct RecordingCreateResponse: Codable, Sendable {
    let id: UUID
    let uploadUrl: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case uploadUrl = "upload_url"
        case expiresAt = "expires_at"
    }
}

/// Full recording details as returned by the API.
struct RecordingResponse: Codable, Sendable {
    let id: UUID
    let userId: UUID
    let subject: String
    let description: String?
    let latitude: Double
    let longitude: Double
    let durationSec: Double
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case subject
        case description
        case latitude
        case longitude
        case durationSec = "duration_sec"
        case status
        case createdAt = "created_at"
    }

    /// Converts this DTO to a domain ``Recording`` model.
    func toDomain() -> Recording {
        Recording(
            id: id,
            userId: userId,
            subject: subject,
            description: description,
            latitude: latitude,
            longitude: longitude,
            durationSeconds: durationSec,
            status: ModerationStatus(rawValue: status) ?? .pendingModeration,
            createdAt: createdAt
        )
    }
}

/// A nearby recording result that includes distance from the query location.
struct NearbyRecordingResponse: Codable, Sendable {
    let id: UUID
    let userId: UUID
    let subject: String
    let description: String?
    let latitude: Double
    let longitude: Double
    let durationSec: Double
    let status: String
    let createdAt: Date
    let distanceMeters: Double
    let creatorDisplayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case subject
        case description
        case latitude
        case longitude
        case durationSec = "duration_sec"
        case status
        case createdAt = "created_at"
        case distanceMeters = "distance_meters"
        case creatorDisplayName = "creator_display_name"
    }

    /// Converts this DTO to a domain ``Recording`` model, including distance.
    func toDomain() -> Recording {
        Recording(
            id: id,
            userId: userId,
            subject: subject,
            description: description,
            latitude: latitude,
            longitude: longitude,
            durationSeconds: durationSec,
            status: ModerationStatus(rawValue: status) ?? .approved,
            createdAt: createdAt,
            distanceMeters: distanceMeters
        )
    }
}

/// Response for obtaining a playback URL for a recording.
struct PlaybackResponse: Codable, Sendable {
    let recordingId: UUID
    let playbackUrl: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case recordingId = "recording_id"
        case playbackUrl = "playback_url"
        case expiresAt = "expires_at"
    }
}
