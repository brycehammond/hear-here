using System.Text.Json.Serialization;

namespace HearHere.Shared.Models.Requests;

public class CreateRecordingRequest
{
    [JsonPropertyName("subject")]
    public string Subject { get; init; } = string.Empty;

    [JsonPropertyName("description")]
    public string? Description { get; init; }

    [JsonPropertyName("latitude")]
    public double Latitude { get; init; }

    [JsonPropertyName("longitude")]
    public double Longitude { get; init; }

    [JsonPropertyName("duration_sec")]
    public int DurationSec { get; init; }
}
