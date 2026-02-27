import Foundation
import Observation

/// Central HTTP client for all Hear Here API communication.
///
/// Uses `URLSession` with `async`/`await` for all network operations.
/// Automatically attaches B2C JWT tokens via ``AuthInterceptor`` and
/// handles 401 retry logic with a single token refresh attempt.
///
/// JSON encoding uses `snake_case` key strategy to match the API's conventions.
/// All responses are decoded with ISO 8601 date handling.
///
/// ## Usage
/// ```swift
/// let recordings = try await apiClient.request(
///     .nearbyRecordings(latitude: 40.7, longitude: -74.0, radiusMeters: 500, cursor: nil),
///     type: PaginatedResponse<NearbyRecordingResponse>.self
/// )
/// ```
@Observable
final class APIClient: @unchecked Sendable {
    private let session: URLSession
    private let baseURL: URL
    private let authInterceptor: AuthInterceptor
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Creates an API client configured for the given environment.
    ///
    /// - Parameters:
    ///   - baseURL: The API base URL (e.g., `https://dev-api.hearhere.app/v1`).
    ///   - authInterceptor: Handles token attachment and refresh.
    ///   - session: The URL session to use for requests. Defaults to `.shared`.
    init(baseURL: URL, authInterceptor: AuthInterceptor, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.authInterceptor = authInterceptor
        self.session = session

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    /// Sends an API request and decodes the response into the specified type.
    ///
    /// Automatically attaches the auth token and retries once on 401 responses
    /// after refreshing the token.
    ///
    /// - Parameters:
    ///   - endpoint: The API endpoint to call.
    ///   - type: The expected response type to decode.
    /// - Returns: The decoded response of type `T`.
    /// - Throws: ``APIError`` if the request fails, the response status is unexpected,
    ///   or the response body cannot be decoded.
    func request<T: Decodable & Sendable>(
        _ endpoint: APIEndpoint,
        type: T.Type
    ) async throws -> T {
        let urlRequest = try buildRequest(for: endpoint)
        let authenticatedRequest = try await authInterceptor.authenticate(urlRequest)

        do {
            return try await performRequest(authenticatedRequest, type: type)
        } catch APIError.unauthorized {
            let refreshedRequest = try await authInterceptor.reauthenticate(urlRequest)
            return try await performRequest(refreshedRequest, type: type)
        }
    }

    /// Sends an API request that returns no response body.
    ///
    /// Used for DELETE and other operations where only the status code matters.
    ///
    /// - Parameter endpoint: The API endpoint to call.
    /// - Throws: ``APIError`` if the request fails or the response status is unexpected.
    func requestVoid(_ endpoint: APIEndpoint) async throws {
        let urlRequest = try buildRequest(for: endpoint)
        let authenticatedRequest = try await authInterceptor.authenticate(urlRequest)

        do {
            try await performVoidRequest(authenticatedRequest)
        } catch APIError.unauthorized {
            let refreshedRequest = try await authInterceptor.reauthenticate(urlRequest)
            try await performVoidRequest(refreshedRequest)
        }
    }

    // MARK: - Private

    private func buildRequest(for endpoint: APIEndpoint) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: true)
        components?.queryItems = endpoint.queryItems

        guard let url = components?.url else {
            throw APIError.unknown(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        return request
    }

    private func performRequest<T: Decodable>(
        _ request: URLRequest,
        type: T.Type
    ) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mapTransportError(error)
        }

        try validateResponse(response)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func performVoidRequest(_ request: URLRequest) async throws {
        let response: URLResponse

        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw mapTransportError(error)
        }

        try validateResponse(response)
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 429:
            throw APIError.rateLimited
        case 400...499:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        case 500...599:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        default:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    private func mapTransportError(_ error: Error) -> APIError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorDataNotAllowed:
                return .networkUnavailable
            default:
                return .unknown(error)
            }
        }
        return .unknown(error)
    }
}

// MARK: - AnyEncodable

/// Type-erasing wrapper for encoding `any Encodable` values.
private struct AnyEncodable: Encodable {
    private let _encode: @Sendable (Encoder) throws -> Void

    init(_ value: any Encodable & Sendable) {
        _encode = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
