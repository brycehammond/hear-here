import Foundation

/// Typed error cases for API operations.
///
/// Maps HTTP status codes and system errors to domain-specific cases
/// that the UI layer can present with appropriate user-facing messages.
enum APIError: Error, Sendable, LocalizedError {
    /// The device has no network connectivity.
    case networkUnavailable

    /// The request was rejected due to an invalid or expired auth token (HTTP 401).
    case unauthorized

    /// The requested resource was not found (HTTP 404).
    case notFound

    /// The server returned an unexpected error status code.
    case serverError(statusCode: Int)

    /// The client is being rate-limited. The UI should back off before retrying.
    case rateLimited

    /// The response body could not be decoded into the expected type.
    case decodingError(Error)

    /// The file upload to the pre-signed URL failed.
    case uploadFailed(underlying: Error)

    /// An error that does not fit any known category.
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "No internet connection. Please check your network and try again."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .notFound:
            return "The requested content could not be found."
        case .serverError(let statusCode):
            return "Something went wrong on our end (error \(statusCode)). Please try again later."
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .decodingError:
            return "We received an unexpected response. Please try again."
        case .uploadFailed:
            return "The upload failed. Please check your connection and try again."
        case .unknown:
            return "An unexpected error occurred. Please try again."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .networkUnavailable:
            return "Check your Wi-Fi or cellular connection."
        case .unauthorized:
            return "Tap to sign in again."
        case .notFound:
            return "The recording may have been deleted."
        case .serverError:
            return "If this keeps happening, please contact support."
        case .rateLimited:
            return "Wait a few seconds before trying again."
        case .decodingError, .uploadFailed, .unknown:
            return "If this keeps happening, try updating the app."
        }
    }
}
