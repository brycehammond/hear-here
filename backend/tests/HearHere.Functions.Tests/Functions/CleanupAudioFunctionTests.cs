using FluentAssertions;
using HearHere.Functions.Functions;
using HearHere.Shared.Data;
using HearHere.Shared.Data.Entities;
using HearHere.Shared.Services;
using Microsoft.Azure.Functions.Worker;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using NSubstitute;
using Xunit;

namespace HearHere.Functions.Tests.Functions;

public class CleanupAudioFunctionTests
{
    private readonly HearHereDbContext _db;
    private readonly IBlobStorageService _blobStorage;
    private readonly CleanupAudioFunction _sut;
    private readonly FunctionContext _functionContext;
    private readonly TimerInfo _timerInfo;

    public CleanupAudioFunctionTests()
    {
        var options = new DbContextOptionsBuilder<HearHereDbContext>()
            .UseInMemoryDatabase(databaseName: $"CleanupAudioTests_{Guid.NewGuid()}")
            .Options;
        _db = new HearHereDbContext(options);

        _blobStorage = Substitute.For<IBlobStorageService>();

        _sut = new CleanupAudioFunction(_db, _blobStorage);

        _functionContext = Substitute.For<FunctionContext>();
        var serviceProvider = Substitute.For<IServiceProvider>();
        _functionContext.InstanceServices.Returns(serviceProvider);

        var loggerFactory = Substitute.For<ILoggerFactory>();
        loggerFactory.CreateLogger(Arg.Any<string>()).Returns(Substitute.For<ILogger>());
        serviceProvider.GetService(typeof(ILoggerFactory)).Returns(loggerFactory);

        _timerInfo = Substitute.For<TimerInfo>();
    }

    private Recording CreateRecording(string status, DateTimeOffset updatedAt, string? blobKey = null)
    {
        return new Recording
        {
            Id = Guid.NewGuid(),
            UserId = Guid.NewGuid(),
            Subject = "Test",
            Status = status,
            UpdatedAt = updatedAt,
            CreatedAt = updatedAt.AddHours(-1),
            AudioBlobKey = blobKey ?? $"recordings/{Guid.NewGuid():N}.aac",
            DurationSec = 60,
            Location = new NetTopologySuite.Geometries.Point(0, 0) { SRID = 4326 }
        };
    }

    [Fact]
    public async Task DeletesOldRejectedRecordings_AndTheirBlobs()
    {
        var old = CreateRecording("rejected", DateTimeOffset.UtcNow.AddDays(-31));
        _db.Recordings.Add(old);
        await _db.SaveChangesAsync();

        await _sut.CleanupOldAudio(_timerInfo, _functionContext);

        var exists = await _db.Recordings.AnyAsync(r => r.Id == old.Id);
        exists.Should().BeFalse();

        await _blobStorage.Received(1).DeleteBlobAsync(old.AudioBlobKey);
    }

    [Fact]
    public async Task DeletesOldDeletedRecordings_AndTheirBlobs()
    {
        var old = CreateRecording("deleted", DateTimeOffset.UtcNow.AddDays(-31));
        _db.Recordings.Add(old);
        await _db.SaveChangesAsync();

        await _sut.CleanupOldAudio(_timerInfo, _functionContext);

        var exists = await _db.Recordings.AnyAsync(r => r.Id == old.Id);
        exists.Should().BeFalse();

        await _blobStorage.Received(1).DeleteBlobAsync(old.AudioBlobKey);
    }

    [Fact]
    public async Task DoesNotDelete_RejectedRecordings_NewerThan30Days()
    {
        var recent = CreateRecording("rejected", DateTimeOffset.UtcNow.AddDays(-10));
        _db.Recordings.Add(recent);
        await _db.SaveChangesAsync();

        await _sut.CleanupOldAudio(_timerInfo, _functionContext);

        var exists = await _db.Recordings.AnyAsync(r => r.Id == recent.Id);
        exists.Should().BeTrue();

        await _blobStorage.DidNotReceiveWithAnyArgs().DeleteBlobAsync(Arg.Any<string>());
    }

    [Fact]
    public async Task DoesNotDelete_ApprovedRecordings_EvenIfOld()
    {
        var oldApproved = CreateRecording("approved", DateTimeOffset.UtcNow.AddDays(-60));
        _db.Recordings.Add(oldApproved);
        await _db.SaveChangesAsync();

        await _sut.CleanupOldAudio(_timerInfo, _functionContext);

        var exists = await _db.Recordings.AnyAsync(r => r.Id == oldApproved.Id);
        exists.Should().BeTrue();
    }

    [Fact]
    public async Task DoesNotDelete_PendingRecordings_EvenIfOld()
    {
        var oldPending = CreateRecording("pending_moderation", DateTimeOffset.UtcNow.AddDays(-60));
        _db.Recordings.Add(oldPending);
        await _db.SaveChangesAsync();

        await _sut.CleanupOldAudio(_timerInfo, _functionContext);

        var exists = await _db.Recordings.AnyAsync(r => r.Id == oldPending.Id);
        exists.Should().BeTrue();
    }

    [Fact]
    public async Task HandlesMultipleRecordings()
    {
        var old1 = CreateRecording("rejected", DateTimeOffset.UtcNow.AddDays(-40));
        var old2 = CreateRecording("deleted", DateTimeOffset.UtcNow.AddDays(-45));
        var recent = CreateRecording("rejected", DateTimeOffset.UtcNow.AddDays(-5));
        _db.Recordings.AddRange(old1, old2, recent);
        await _db.SaveChangesAsync();

        await _sut.CleanupOldAudio(_timerInfo, _functionContext);

        (await _db.Recordings.AnyAsync(r => r.Id == old1.Id)).Should().BeFalse();
        (await _db.Recordings.AnyAsync(r => r.Id == old2.Id)).Should().BeFalse();
        (await _db.Recordings.AnyAsync(r => r.Id == recent.Id)).Should().BeTrue();
    }

    [Fact]
    public async Task ContinuesProcessing_WhenBlobDeleteFails()
    {
        var old1 = CreateRecording("rejected", DateTimeOffset.UtcNow.AddDays(-40));
        var old2 = CreateRecording("rejected", DateTimeOffset.UtcNow.AddDays(-45));
        _db.Recordings.AddRange(old1, old2);
        await _db.SaveChangesAsync();

        _blobStorage.DeleteBlobAsync(old1.AudioBlobKey)
            .Returns(Task.FromException(new Exception("Blob not found")));
        _blobStorage.DeleteBlobAsync(old2.AudioBlobKey)
            .Returns(Task.CompletedTask);

        await _sut.CleanupOldAudio(_timerInfo, _functionContext);

        // old1 should still exist because exception prevented Remove
        // old2 should be deleted
        (await _db.Recordings.AnyAsync(r => r.Id == old2.Id)).Should().BeFalse();
    }

    [Fact]
    public async Task NoRecordingsToCleanup_CompletesWithoutError()
    {
        var act = () => _sut.CleanupOldAudio(_timerInfo, _functionContext);

        await act.Should().NotThrowAsync();
    }
}
