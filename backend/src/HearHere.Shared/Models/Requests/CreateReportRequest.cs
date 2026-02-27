using System.Text.Json.Serialization;

namespace HearHere.Shared.Models.Requests;

public class CreateReportRequest
{
    [JsonPropertyName("recording_id")]
    public Guid RecordingId { get; init; }

    [JsonPropertyName("reason")]
    public string Reason { get; init; } = string.Empty;

    [JsonPropertyName("description")]
    public string? Description { get; init; }
}
