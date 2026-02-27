using System.Text.Json.Serialization;

namespace HearHere.Shared.Models.Responses;

public class PlaybackResponse
{
    [JsonPropertyName("playback_url")]
    public string PlaybackUrl { get; init; } = string.Empty;

    [JsonPropertyName("expires_at")]
    public DateTimeOffset ExpiresAt { get; init; }

    [JsonPropertyName("duration_sec")]
    public int DurationSec { get; init; }

    [JsonPropertyName("format")]
    public string Format { get; init; } = "aac";
}
