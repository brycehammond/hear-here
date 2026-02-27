using System.Text.Json.Serialization;

namespace HearHere.Shared.Models.Responses;

public class ModerationStatsResponse
{
    [JsonPropertyName("pending_review")]
    public int PendingReview { get; init; }

    [JsonPropertyName("reviewed_today")]
    public int ReviewedToday { get; init; }

    [JsonPropertyName("auto_approved_today")]
    public int AutoApprovedToday { get; init; }

    [JsonPropertyName("auto_rejected_today")]
    public int AutoRejectedToday { get; init; }

    [JsonPropertyName("avg_review_time_sec")]
    public double AvgReviewTimeSec { get; init; }
}
