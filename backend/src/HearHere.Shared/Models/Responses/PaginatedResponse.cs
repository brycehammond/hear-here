using System.Text.Json.Serialization;

namespace HearHere.Shared.Models.Responses;

public class PaginatedResponse<T>
{
    [JsonPropertyName("items")]
    public List<T> Items { get; init; } = [];

    [JsonPropertyName("next_cursor")]
    public string? NextCursor { get; init; }
}
