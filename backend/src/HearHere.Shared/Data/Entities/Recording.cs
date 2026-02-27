using System;
using NetTopologySuite.Geometries;

namespace HearHere.Shared.Data.Entities;

public class Recording
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string Subject { get; set; } = string.Empty;
    public string? Description { get; set; }
    public Point Location { get; set; } = null!;
    public string? LocationName { get; set; }
    public string? City { get; set; }
    public string? Region { get; set; }
    public string? Country { get; set; }
    public string AudioBlobKey { get; set; } = string.Empty;
    public string AudioFormat { get; set; } = "aac";
    public int DurationSec { get; set; }
    public int? FileSizeBytes { get; set; }
    public string Status { get; set; } = "pending_moderation";
    public string? Transcript { get; set; }
    public string? ModerationScores { get; set; }
    public string? Category { get; set; }
    public int PlayCount { get; set; }
    public int LikeCount { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public DateTimeOffset? DeletedAt { get; set; }

    public User User { get; set; } = null!;
    public ICollection<ModerationRecord> ModerationRecords { get; set; } = [];
    public ICollection<Play> Plays { get; set; } = [];
    public ICollection<Like> Likes { get; set; } = [];
    public ICollection<Report> Reports { get; set; } = [];
    public ICollection<RecordingTag> RecordingTags { get; set; } = [];
}
