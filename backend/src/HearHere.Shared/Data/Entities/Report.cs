using System;

namespace HearHere.Shared.Data.Entities;

public class Report
{
    public Guid Id { get; set; }
    public Guid RecordingId { get; set; }
    public Guid UserId { get; set; }
    public string ReasonCode { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string Status { get; set; } = "open";
    public Guid? ResolvedBy { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? ResolvedAt { get; set; }

    public Recording Recording { get; set; } = null!;
    public User User { get; set; } = null!;
    public User? ResolvedByUser { get; set; }
}
