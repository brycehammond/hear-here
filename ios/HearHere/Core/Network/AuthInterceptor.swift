import Foundation

/// Protocol for providing authentication tokens to the API client.
///
/// This abstraction allows the ``APIClient`` to obtain JWT tokens without
/// depending directly on the auth implementation, enabling testing with mock token providers.
protocol TokenProviding: Sendable {
    /// Returns the current valid JWT token, refreshing if necessary.
    /// - Returns: A valid JWT token string.
    /// - Throws: If the token cannot be obtained or refreshed.
    func currentToken() async throws -> String

    /// Forces a token refresh, bypassing any cached token.
    /// - Returns: A freshly obtained JWT token string.
    /// - Throws: If the token refresh fails.
    func refreshToken() async throws -> String
}

/// Handles JWT token attachment and automatic refresh on 401 responses.
///
/// The interceptor attaches the B2C JWT to every outgoing request as a
/// Bearer token in the Authorization header. When a 401 response is received,
/// it refreshes the token once and retries the original request.
final class AuthInterceptor: Sendable {
    private let tokenProvider: TokenProviding

    /// Creates an auth interceptor with the given token provider.
    /// - Parameter tokenProvider: The source of JWT tokens, typically wrapping MSAL.
    init(tokenProvider: TokenProviding) {
        self.tokenProvider = tokenProvider
    }

    /// Attaches the current auth token to the request's Authorization header.
    /// - Parameter request: The outgoing URL request to authenticate.
    /// - Returns: The request with the Bearer token attached.
    func authenticate(_ request: URLRequest) async throws -> URLRequest {
        var authenticatedRequest = request
        let token = try await tokenProvider.currentToken()
        authenticatedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return authenticatedRequest
    }

    /// Attempts to refresh the auth token and re-authenticate the request.
    ///
    /// Called when a 401 response is received. This method forces a token refresh
    /// and attaches the new token to the request for a single retry attempt.
    ///
    /// - Parameter request: The original request that received a 401.
    /// - Returns: The request with a refreshed Bearer token attached.
    func reauthenticate(_ request: URLRequest) async throws -> URLRequest {
        var refreshedRequest = request
        let newToken = try await tokenProvider.refreshToken()
        refreshedRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
        return refreshedRequest
    }
}
