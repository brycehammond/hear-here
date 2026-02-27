using System.Text.Json.Serialization;

namespace HearHere.Shared.Models.Responses;

public class ReportResponse
{
    [JsonPropertyName("id")]
    public Guid Id { get; init; }

    [JsonPropertyName("recording_id")]
    public Guid RecordingId { get; init; }

    [JsonPropertyName("status")]
    public string Status { get; init; } = string.Empty;

    [JsonPropertyName("created_at")]
    public DateTimeOffset CreatedAt { get; init; }
}
