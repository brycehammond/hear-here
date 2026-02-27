using System.Text.Json.Serialization;

namespace HearHere.Shared.Models.Requests;

public class ModerationDecisionRequest
{
    [JsonPropertyName("decision")]
    public string Decision { get; init; } = string.Empty;

    [JsonPropertyName("notes")]
    public string? Notes { get; init; }
}
