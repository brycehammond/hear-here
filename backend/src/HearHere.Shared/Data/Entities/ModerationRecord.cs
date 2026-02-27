using System;

namespace HearHere.Shared.Data.Entities;

public class ModerationRecord
{
    public Guid Id { get; set; }
    public Guid RecordingId { get; set; }
    public string Action { get; set; } = string.Empty;
    public string ActorType { get; set; } = string.Empty;
    public string? ActorId { get; set; }
    public string FromStatus { get; set; } = string.Empty;
    public string ToStatus { get; set; } = string.Empty;
    public string? Scores { get; set; }
    public string? Reason { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    public Recording Recording { get; set; } = null!;
}
