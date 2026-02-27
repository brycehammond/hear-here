using System.Text.Json.Serialization;

namespace HearHere.Shared.Models.Responses;

public class ErrorResponse
{
    [JsonPropertyName("error")]
    public ErrorDetail Error { get; init; } = null!;
}

public class ErrorDetail
{
    [JsonPropertyName("code")]
    public string Code { get; init; } = string.Empty;

    [JsonPropertyName("message")]
    public string Message { get; init; } = string.Empty;

    [JsonPropertyName("details")]
    public object? Details { get; init; }
}
