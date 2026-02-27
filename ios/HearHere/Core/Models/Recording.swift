import CoreLocation
import Foundation

/// Domain model representing an audio recording pinned to a geographic location.
///
/// This is the primary domain entity in Hear Here. A recording captures a user's
/// audio story along with its metadata and geographic coordinates. Recordings
/// progress through the ``ModerationStatus`` lifecycle from upload to publication.
struct Recording: Identifiable, Hashable, Sendable {
    /// The unique server-assigned identifier for this recording.
    let id: UUID

    /// The identifier of the user who created this recording.
    let userId: UUID

    /// The title or subject of the recording (max 200 characters).
    let subject: String

    /// An optional longer description of the recording's content (max 1000 characters).
    let description: String?

    /// The latitude where this recording is pinned.
    let latitude: Double

    /// The longitude where this recording is pinned.
    let longitude: Double

    /// The duration of the audio in seconds.
    let durationSeconds: Double

    /// The current moderation status of this recording.
    var status: ModerationStatus

    /// The date and time when this recording was created.
    let createdAt: Date

    /// The distance in meters from the user's current location, if available.
    /// This is typically populated only for nearby recording queries.
    var distanceMeters: Double?

    /// A `CLLocationCoordinate2D` derived from the recording's latitude and longitude.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// A formatted string representing the recording duration (e.g., "2:34").
    var formattedDuration: String {
        let minutes = Int(durationSeconds) / 60
        let seconds = Int(durationSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// A formatted string representing the distance (e.g., "120m away" or "1.2km away").
    var formattedDistance: String? {
        guard let distance = distanceMeters else { return nil }
        if distance < 1000 {
            return "\(Int(distance))m away"
        } else {
            return String(format: "%.1fkm away", distance / 1000)
        }
    }
}
