using FluentAssertions;
using HearHere.Functions.Functions;
using HearHere.Shared.Data;
using HearHere.Shared.Data.Entities;
using Microsoft.Azure.Functions.Worker;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using NSubstitute;
using Xunit;

namespace HearHere.Functions.Tests.Functions;

public class CleanupUploadsFunctionTests
{
    private readonly HearHereDbContext _db;
    private readonly CleanupUploadsFunction _sut;
    private readonly FunctionContext _functionContext;
    private readonly TimerInfo _timerInfo;

    public CleanupUploadsFunctionTests()
    {
        var options = new DbContextOptionsBuilder<HearHereDbContext>()
            .UseInMemoryDatabase(databaseName: $"CleanupUploadsTests_{Guid.NewGuid()}")
            .Options;
        _db = new HearHereDbContext(options);

        _sut = new CleanupUploadsFunction(_db);

        _functionContext = Substitute.For<FunctionContext>();
        var serviceProvider = Substitute.For<IServiceProvider>();
        _functionContext.InstanceServices.Returns(serviceProvider);

        var loggerFactory = Substitute.For<ILoggerFactory>();
        loggerFactory.CreateLogger(Arg.Any<string>()).Returns(Substitute.For<ILogger>());
        serviceProvider.GetService(typeof(ILoggerFactory)).Returns(loggerFactory);

        _timerInfo = Substitute.For<TimerInfo>();
    }

    private Recording CreateRecording(string status, DateTimeOffset createdAt)
    {
        return new Recording
        {
            Id = Guid.NewGuid(),
            UserId = Guid.NewGuid(),
            Subject = "Test",
            Status = status,
            CreatedAt = createdAt,
            AudioBlobKey = $"recordings/{Guid.NewGuid():N}.aac",
            DurationSec = 60,
            Location = new NetTopologySuite.Geometries.Point(0, 0) { SRID = 4326 }
        };
    }

    [Fact]
    public async Task ExpiresStale_PendingUpload_OlderThanOneHour()
    {
        var stale = CreateRecording("pending_upload", DateTimeOffset.UtcNow.AddHours(-2));
        _db.Recordings.Add(stale);
        await _db.SaveChangesAsync();

        await _sut.CleanupStaleUploads(_timerInfo, _functionContext);

        var updated = await _db.Recordings.FindAsync(stale.Id);
        updated!.Status.Should().Be("rejected");
        updated.DeletedAt.Should().NotBeNull();
    }

    [Fact]
    public async Task DoesNotExpire_PendingUpload_NewerThanOneHour()
    {
        var recent = CreateRecording("pending_upload", DateTimeOffset.UtcNow.AddMinutes(-30));
        _db.Recordings.Add(recent);
        await _db.SaveChangesAsync();

        await _sut.CleanupStaleUploads(_timerInfo, _functionContext);

        var updated = await _db.Recordings.FindAsync(recent.Id);
        updated!.Status.Should().Be("pending_upload");
        updated.DeletedAt.Should().BeNull();
    }

    [Fact]
    public async Task DoesNotExpire_OtherStatuses_EvenIfOld()
    {
        var approved = CreateRecording("approved", DateTimeOffset.UtcNow.AddHours(-2));
        var pendingMod = CreateRecording("pending_moderation", DateTimeOffset.UtcNow.AddHours(-2));
        _db.Recordings.AddRange(approved, pendingMod);
        await _db.SaveChangesAsync();

        await _sut.CleanupStaleUploads(_timerInfo, _functionContext);

        var updatedApproved = await _db.Recordings.FindAsync(approved.Id);
        updatedApproved!.Status.Should().Be("approved");

        var updatedPendingMod = await _db.Recordings.FindAsync(pendingMod.Id);
        updatedPendingMod!.Status.Should().Be("pending_moderation");
    }

    [Fact]
    public async Task CreatesModerationRecord_ForExpiredUploads()
    {
        var stale = CreateRecording("pending_upload", DateTimeOffset.UtcNow.AddHours(-2));
        _db.Recordings.Add(stale);
        await _db.SaveChangesAsync();

        await _sut.CleanupStaleUploads(_timerInfo, _functionContext);

        var record = await _db.ModerationRecords.FirstOrDefaultAsync(m => m.RecordingId == stale.Id);
        record.Should().NotBeNull();
        record!.Action.Should().Be("auto_reject");
        record.ActorType.Should().Be("system");
        record.FromStatus.Should().Be("pending_upload");
        record.ToStatus.Should().Be("rejected");
        record.Reason.Should().Contain("pending_upload older than 1 hour");
    }

    [Fact]
    public async Task HandlesMultipleStaleRecordings()
    {
        var stale1 = CreateRecording("pending_upload", DateTimeOffset.UtcNow.AddHours(-3));
        var stale2 = CreateRecording("pending_upload", DateTimeOffset.UtcNow.AddHours(-5));
        _db.Recordings.AddRange(stale1, stale2);
        await _db.SaveChangesAsync();

        await _sut.CleanupStaleUploads(_timerInfo, _functionContext);

        var updated1 = await _db.Recordings.FindAsync(stale1.Id);
        var updated2 = await _db.Recordings.FindAsync(stale2.Id);
        updated1!.Status.Should().Be("rejected");
        updated2!.Status.Should().Be("rejected");
    }

    [Fact]
    public async Task NoStaleRecordings_CompletesWithoutError()
    {
        var recent = CreateRecording("pending_upload", DateTimeOffset.UtcNow.AddMinutes(-10));
        _db.Recordings.Add(recent);
        await _db.SaveChangesAsync();

        var act = () => _sut.CleanupStaleUploads(_timerInfo, _functionContext);

        await act.Should().NotThrowAsync();
    }
}
