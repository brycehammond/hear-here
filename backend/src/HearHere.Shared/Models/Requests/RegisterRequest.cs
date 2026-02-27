using System.Text.Json.Serialization;

namespace HearHere.Shared.Models.Requests;

public class RegisterRequest
{
    [JsonPropertyName("display_name")]
    public string DisplayName { get; init; } = string.Empty;
}
