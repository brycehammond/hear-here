using System.Text.Json.Serialization;

namespace HearHere.Shared.Models.Responses;

public class RecordingCreateResponse
{
    [JsonPropertyName("id")]
    public Guid Id { get; init; }

    [JsonPropertyName("upload_url")]
    public string UploadUrl { get; init; } = string.Empty;

    [JsonPropertyName("upload_expires_at")]
    public DateTimeOffset UploadExpiresAt { get; init; }

    [JsonPropertyName("status")]
    public string Status { get; init; } = "pending_upload";
}
