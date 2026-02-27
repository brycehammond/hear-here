using System.Text.Json.Serialization;

namespace HearHere.Shared.Models.Responses;

public class UploadCompleteResponse
{
    [JsonPropertyName("id")]
    public Guid Id { get; init; }

    [JsonPropertyName("status")]
    public string Status { get; init; } = string.Empty;
}
