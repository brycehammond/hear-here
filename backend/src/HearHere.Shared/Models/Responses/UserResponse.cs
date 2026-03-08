using System.Text.Json.Serialization;

namespace HearHere.Shared.Models.Responses;

public class UserResponse
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = string.Empty;

    [JsonPropertyName("display_name")]
    public string DisplayName { get; init; } = string.Empty;

    [JsonPropertyName("identity_provider")]
    public string IdentityProvider { get; init; } = "entra";

    [JsonPropertyName("recording_count")]
    public int RecordingCount { get; init; }

    [JsonPropertyName("created_at")]
    public DateTimeOffset CreatedAt { get; init; }
}
