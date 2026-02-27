using System;

namespace HearHere.Shared.Data.Entities;

public class Tag
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public DateTimeOffset CreatedAt { get; set; }

    public ICollection<RecordingTag> RecordingTags { get; set; } = [];
}
