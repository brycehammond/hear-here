import Foundation

/// Request body for reporting a recording that violates community guidelines.
struct CreateReportRequest: Codable, Sendable {
    let recordingId: UUID
    let reason: String

    enum CodingKeys: String, CodingKey {
        case recordingId = "recording_id"
        case reason
    }
}

/// Response after successfully creating a content report.
struct ReportResponse: Codable, Sendable {
    let id: UUID
    let recordingId: UUID
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case recordingId = "recording_id"
        case status
        case createdAt = "created_at"
    }
}
