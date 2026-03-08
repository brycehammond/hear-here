using System;

namespace HearHere.Shared.Data.Entities;

public class User
{
    public Guid Id { get; set; }
    public string ExternalId { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string? AvatarBlobKey { get; set; }
    public string? ApnsToken { get; set; }
    public string IdentityProvider { get; set; } = "entra";
    public string Role { get; set; } = "user";
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public ICollection<Recording> Recordings { get; set; } = [];
    public ICollection<Play> Plays { get; set; } = [];
    public ICollection<Like> Likes { get; set; } = [];
    public ICollection<Report> Reports { get; set; } = [];
}
