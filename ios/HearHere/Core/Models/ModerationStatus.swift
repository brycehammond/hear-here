import Foundation

/// Represents the moderation lifecycle state of a recording.
///
/// Recordings progress through these states from initial upload through
/// the content moderation pipeline. The status determines visibility
/// and available actions for both the creator and other users.
enum ModerationStatus: String, Codable, Sendable, CaseIterable {
    /// The recording has been created locally but not yet uploaded to the server.
    case pendingUpload = "pending_upload"

    /// The recording has been uploaded and is awaiting automated moderation.
    case pendingModeration = "pending_moderation"

    /// The recording passed automated moderation and is awaiting human review.
    case pendingReview = "pending_review"

    /// The recording has been approved and is publicly discoverable.
    case approved

    /// The recording was rejected for violating community guidelines.
    case rejected

    /// A user-facing display name for this status.
    var displayName: String {
        switch self {
        case .pendingUpload:
            return "Uploading"
        case .pendingModeration, .pendingReview:
            return "Under Review"
        case .approved:
            return "Published"
        case .rejected:
            return "Not Published"
        }
    }

    /// The SF Symbol icon name appropriate for this status.
    var iconName: String {
        switch self {
        case .pendingUpload:
            return "arrow.up.circle"
        case .pendingModeration, .pendingReview:
            return "clock"
        case .approved:
            return "checkmark.circle.fill"
        case .rejected:
            return "xmark.circle.fill"
        }
    }

    /// Whether the recording is visible to users other than the creator.
    var isPubliclyVisible: Bool {
        self == .approved
    }

    /// Whether the recording is still being processed in the moderation pipeline.
    var isPending: Bool {
        switch self {
        case .pendingUpload, .pendingModeration, .pendingReview:
            return true
        case .approved, .rejected:
            return false
        }
    }
}
