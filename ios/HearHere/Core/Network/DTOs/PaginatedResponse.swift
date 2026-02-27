import Foundation

/// A generic paginated API response that wraps a collection of items with cursor-based pagination.
///
/// The API uses cursor-based pagination rather than offset-based pagination
/// for consistent results when data changes between page fetches.
///
/// - Parameter T: The type of items contained in this page. Must be `Codable` and `Sendable`.
struct PaginatedResponse<T: Codable & Sendable>: Codable, Sendable {
    /// The items returned in this page of results.
    let items: [T]

    /// The cursor to use when fetching the next page.
    /// `nil` indicates there are no more pages.
    let nextCursor: String?

    /// The total count of items matching the query, if provided by the server.
    let totalCount: Int?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case totalCount = "total_count"
    }

    /// Whether there are more pages available after this one.
    var hasMore: Bool {
        nextCursor != nil
    }
}
