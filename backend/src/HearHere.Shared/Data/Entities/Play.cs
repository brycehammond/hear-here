using System;

namespace HearHere.Shared.Data.Entities;

public class Play
{
    public Guid Id { get; set; }
    public Guid RecordingId { get; set; }
    public Guid UserId { get; set; }
    public int DurationSec { get; set; }
    public bool Completed { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    public Recording Recording { get; set; } = null!;
    public User User { get; set; } = null!;
}
