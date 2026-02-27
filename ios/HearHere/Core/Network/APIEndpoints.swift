import Foundation

/// Defines all API endpoints with their HTTP method, path, and optional request body.
///
/// Each case represents a single API operation. The ``APIClient`` uses these
/// definitions to construct `URLRequest` objects with the correct method, path,
/// and serialized body.
enum APIEndpoint: Sendable {
    // MARK: - User Endpoints

    /// Register a new user account after authentication.
    case register(RegisterRequest)

    /// Fetch the current authenticated user's profile.
    case getMe

    /// Update the current user's profile (display name).
    case updateMe(UpdateUserRequest)

    // MARK: - Recording Endpoints

    /// Create a new recording and receive a pre-signed upload URL.
    case createRecording(CreateRecordingRequest)

    /// Notify the server that an upload has completed.
    case uploadComplete(recordingId: UUID)

    /// Fetch a single recording by its identifier.
    case getRecording(id: UUID)

    /// Fetch the current user's recordings with cursor-based pagination.
    case myRecordings(cursor: String?, limit: Int)

    /// Fetch nearby recordings within a radius of a geographic point.
    case nearbyRecordings(latitude: Double, longitude: Double, radiusMeters: Double, cursor: String?)

    /// Get a signed playback URL for streaming a recording.
    case playback(recordingId: UUID)

    /// Delete a recording owned by the current user.
    case deleteRecording(id: UUID)

    // MARK: - Account Endpoints

    /// Delete the current user's account and all associated data.
    case deleteAccount

    // MARK: - Report Endpoints

    /// Report a recording for violating community guidelines.
    case createReport(CreateReportRequest)

    /// The HTTP method for this endpoint.
    var method: String {
        switch self {
        case .register, .createRecording, .uploadComplete, .createReport:
            return "POST"
        case .getMe, .getRecording, .myRecordings, .nearbyRecordings, .playback:
            return "GET"
        case .updateMe:
            return "PATCH"
        case .deleteRecording, .deleteAccount:
            return "DELETE"
        }
    }

    /// The URL path relative to the API base URL.
    var path: String {
        switch self {
        case .register:
            return "/users/register"
        case .getMe:
            return "/users/me"
        case .updateMe:
            return "/users/me"
        case .createRecording:
            return "/recordings"
        case .uploadComplete(let recordingId):
            return "/recordings/\(recordingId)/upload-complete"
        case .getRecording(let id):
            return "/recordings/\(id)"
        case .myRecordings:
            return "/recordings/mine"
        case .nearbyRecordings:
            return "/recordings/nearby"
        case .playback(let recordingId):
            return "/recordings/\(recordingId)/playback"
        case .deleteRecording(let id):
            return "/recordings/\(id)"
        case .deleteAccount:
            return "/users/me"
        case .createReport:
            return "/reports"
        }
    }

    /// Query parameters for GET requests, if any.
    var queryItems: [URLQueryItem]? {
        switch self {
        case .myRecordings(let cursor, let limit):
            var items = [URLQueryItem(name: "limit", value: String(limit))]
            if let cursor {
                items.append(URLQueryItem(name: "cursor", value: cursor))
            }
            return items

        case .nearbyRecordings(let latitude, let longitude, let radiusMeters, let cursor):
            var items = [
                URLQueryItem(name: "lat", value: String(latitude)),
                URLQueryItem(name: "lng", value: String(longitude)),
                URLQueryItem(name: "radius", value: String(Int(radiusMeters))),
            ]
            if let cursor {
                items.append(URLQueryItem(name: "cursor", value: cursor))
            }
            return items

        default:
            return nil
        }
    }

    /// The encodable request body, if this endpoint sends a JSON body.
    var body: (any Encodable & Sendable)? {
        switch self {
        case .register(let request):
            return request
        case .updateMe(let request):
            return request
        case .createRecording(let request):
            return request
        case .createReport(let request):
            return request
        default:
            return nil
        }
    }
}
