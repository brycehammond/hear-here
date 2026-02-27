using HearHere.Shared.Data;
using HearHere.Shared.Data.Entities;
using Microsoft.Extensions.DependencyInjection;
using NetTopologySuite.Geometries;

namespace HearHere.Api.Tests.Endpoints;

public static class TestDataHelper
{
    public static User CreateUser(
        HearHereDbContext db,
        string externalId = "test-user-1",
        string displayName = "Test User",
        string role = "user")
    {
        var user = new User
        {
            Id = Guid.NewGuid(),
            ExternalId = externalId,
            DisplayName = displayName,
            Role = role,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };

        db.Users.Add(user);
        db.SaveChanges();
        return user;
    }

    public static Recording CreateRecording(
        HearHereDbContext db,
        Guid userId,
        string status = "approved",
        string subject = "Test Recording")
    {
        var recording = new Recording
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Subject = subject,
            Location = new Point(0, 0) { SRID = 4326 },
            AudioBlobKey = $"recordings/{Guid.NewGuid():N}.aac",
            DurationSec = 30,
            Status = status,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };

        db.Recordings.Add(recording);
        db.SaveChanges();
        return recording;
    }

    public static Report CreateReport(
        HearHereDbContext db,
        Guid recordingId,
        Guid userId,
        string reason = "spam")
    {
        var report = new Report
        {
            Id = Guid.NewGuid(),
            RecordingId = recordingId,
            UserId = userId,
            ReasonCode = reason,
            Status = "submitted",
            CreatedAt = DateTimeOffset.UtcNow
        };

        db.Reports.Add(report);
        db.SaveChanges();
        return report;
    }

    public static HearHereDbContext GetDbContext(IServiceProvider services)
    {
        var scope = services.CreateScope();
        return scope.ServiceProvider.GetRequiredService<HearHereDbContext>();
    }
}
