using System.Text.Json.Serialization;

namespace HearHere.Shared.Models.Responses;

public class NearbyRecordingResponse : RecordingResponse
{
    [JsonPropertyName("distance_m")]
    public double DistanceM { get; init; }
}
