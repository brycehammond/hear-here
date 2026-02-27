using System.Text.Json.Serialization;

namespace HearHere.Shared.Models.Responses;

public class ModerationDecisionResponse
{
    [JsonPropertyName("id")]
    public Guid Id { get; init; }

    [JsonPropertyName("status")]
    public string Status { get; init; } = string.Empty;

    [JsonPropertyName("reviewed_by")]
    public string ReviewedBy { get; init; } = string.Empty;

    [JsonPropertyName("reviewed_at")]
    public DateTimeOffset ReviewedAt { get; init; }
}
