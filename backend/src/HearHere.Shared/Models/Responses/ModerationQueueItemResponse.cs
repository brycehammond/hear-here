using System.Text.Json.Serialization;

namespace HearHere.Shared.Models.Responses;

public class ModerationQueueItemResponse
{
    [JsonPropertyName("id")]
    public Guid Id { get; init; }

    [JsonPropertyName("subject")]
    public string Subject { get; init; } = string.Empty;

    [JsonPropertyName("description")]
    public string? Description { get; init; }

    [JsonPropertyName("duration_sec")]
    public int DurationSec { get; init; }

    [JsonPropertyName("transcript")]
    public string? Transcript { get; init; }

    [JsonPropertyName("moderation_result")]
    public object? ModerationResult { get; init; }

    [JsonPropertyName("report_count")]
    public int ReportCount { get; init; }

    [JsonPropertyName("playback_url")]
    public string? PlaybackUrl { get; init; }

    [JsonPropertyName("created_at")]
    public DateTimeOffset CreatedAt { get; init; }

    [JsonPropertyName("user")]
    public ModerationQueueUserResponse User { get; init; } = null!;
}

public class ModerationQueueUserResponse
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = string.Empty;

    [JsonPropertyName("display_name")]
    public string DisplayName { get; init; } = string.Empty;
}
