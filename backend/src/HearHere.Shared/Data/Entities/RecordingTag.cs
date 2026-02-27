using System;

namespace HearHere.Shared.Data.Entities;

public class RecordingTag
{
    public Guid RecordingId { get; set; }
    public int TagId { get; set; }

    public Recording Recording { get; set; } = null!;
    public Tag Tag { get; set; } = null!;
}
