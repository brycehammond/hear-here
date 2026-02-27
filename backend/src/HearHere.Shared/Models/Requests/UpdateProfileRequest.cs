using System.Text.Json.Serialization;

namespace HearHere.Shared.Models.Requests;

public class UpdateProfileRequest
{
    [JsonPropertyName("display_name")]
    public string? DisplayName { get; init; }
}
