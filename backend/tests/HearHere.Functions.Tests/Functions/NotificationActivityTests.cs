using FluentAssertions;
using HearHere.Functions.Functions;
using HearHere.Shared.Data;
using HearHere.Shared.Data.Entities;
using HearHere.Shared.Services;
using Microsoft.Azure.Functions.Worker;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using NetTopologySuite.Geometries;
using NSubstitute;
using NSubstitute.ExceptionExtensions;
using Xunit;

namespace HearHere.Functions.Tests.Functions;

public class NotificationActivityTests
{
    private readonly HearHereDbContext _db;
    private readonly INotificationService _notificationService;
    private readonly NotificationActivity _sut;
    private readonly FunctionContext _functionContext;

    public NotificationActivityTests()
    {
        var options = new DbContextOptionsBuilder<HearHereDbContext>()
            .UseInMemoryDatabase($"NotificationTests_{Guid.NewGuid()}")
            .Options;
        _db = new HearHereDbContext(options);

        _notificationService = Substitute.For<INotificationService>();
        _sut = new NotificationActivity(_db, _notificationService);

        _functionContext = Substitute.For<FunctionContext>();
        var serviceProvider = Substitute.For<IServiceProvider>();
        _functionContext.InstanceServices.Returns(serviceProvider);

        var loggerFactory = Substitute.For<ILoggerFactory>();
        loggerFactory.CreateLogger(Arg.Any<string>()).Returns(Substitute.For<ILogger>());
        serviceProvider.GetService(typeof(ILoggerFactory)).Returns(loggerFactory);
    }

    private async Task<(User user, Recording recording)> SeedRecordingWithUser(
        string status = "approved",
        string? apnsToken = "test-device-token-12345")
    {
        var user = new User
        {
            Id = Guid.NewGuid(),
            ExternalId = $"ext-{Guid.NewGuid()}",
            DisplayName = "Test User",
            ApnsToken = apnsToken
        };
        _db.Users.Add(user);

        var recording = new Recording
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            Subject = "Test Recording",
            Status = status,
            AudioBlobKey = "recordings/test.aac",
            DurationSec = 60,
            Location = new Point(0, 0) { SRID = 4326 }
        };
        _db.Recordings.Add(recording);
        await _db.SaveChangesAsync();

        return (user, recording);
    }

    [Fact]
    public async Task SendNotification_WithApnsToken_SendsPushNotification()
    {
        var (user, recording) = await SeedRecordingWithUser("approved", "device-token-abc");

        await _sut.SendNotification(recording.Id, _functionContext);

        await _notificationService.Received(1).SendPushNotificationAsync(
            "device-token-abc",
            "Recording Approved",
            $"Your recording 'Test Recording' is now live!",
            Arg.Any<Dictionary<string, string>>());
    }

    [Fact]
    public async Task SendNotification_WithoutApnsToken_SkipsNotification()
    {
        var (_, recording) = await SeedRecordingWithUser("approved", null);

        await _sut.SendNotification(recording.Id, _functionContext);

        await _notificationService.DidNotReceive().SendPushNotificationAsync(
            Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<Dictionary<string, string>>());
    }

    [Fact]
    public async Task SendNotification_WithEmptyApnsToken_SkipsNotification()
    {
        var (_, recording) = await SeedRecordingWithUser("approved", "");

        await _sut.SendNotification(recording.Id, _functionContext);

        await _notificationService.DidNotReceive().SendPushNotificationAsync(
            Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<Dictionary<string, string>>());
    }

    [Fact]
    public async Task SendNotification_ApprovedRecording_CorrectMessage()
    {
        var (_, recording) = await SeedRecordingWithUser("approved");

        await _sut.SendNotification(recording.Id, _functionContext);

        await _notificationService.Received(1).SendPushNotificationAsync(
            Arg.Any<string>(),
            "Recording Approved",
            "Your recording 'Test Recording' is now live!",
            Arg.Any<Dictionary<string, string>>());
    }

    [Fact]
    public async Task SendNotification_RejectedRecording_CorrectMessage()
    {
        var (_, recording) = await SeedRecordingWithUser("rejected");

        await _sut.SendNotification(recording.Id, _functionContext);

        await _notificationService.Received(1).SendPushNotificationAsync(
            Arg.Any<string>(),
            "Recording Not Approved",
            "Your recording 'Test Recording' could not be approved.",
            Arg.Any<Dictionary<string, string>>());
    }

    [Fact]
    public async Task SendNotification_PendingReviewRecording_CorrectMessage()
    {
        var (_, recording) = await SeedRecordingWithUser("pending_review");

        await _sut.SendNotification(recording.Id, _functionContext);

        await _notificationService.Received(1).SendPushNotificationAsync(
            Arg.Any<string>(),
            "Recording Under Review",
            "Your recording 'Test Recording' is under review.",
            Arg.Any<Dictionary<string, string>>());
    }

    [Fact]
    public async Task SendNotification_IncludesCustomData()
    {
        var (_, recording) = await SeedRecordingWithUser("approved");

        await _sut.SendNotification(recording.Id, _functionContext);

        await _notificationService.Received(1).SendPushNotificationAsync(
            Arg.Any<string>(),
            Arg.Any<string>(),
            Arg.Any<string>(),
            Arg.Is<Dictionary<string, string>>(d =>
                d["recording_id"] == recording.Id.ToString() &&
                d["status"] == "approved"));
    }

    [Fact]
    public async Task SendNotification_RecordingNotFound_DoesNotThrow()
    {
        var act = () => _sut.SendNotification(Guid.NewGuid(), _functionContext);

        await act.Should().NotThrowAsync();

        await _notificationService.DidNotReceive().SendPushNotificationAsync(
            Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<Dictionary<string, string>>());
    }

    [Fact]
    public async Task SendNotification_ServiceThrows_HandlesGracefully()
    {
        var (_, recording) = await SeedRecordingWithUser("approved");

        _notificationService.SendPushNotificationAsync(
            Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<Dictionary<string, string>>())
            .ThrowsAsync(new Exception("Notification hub unavailable"));

        var act = () => _sut.SendNotification(recording.Id, _functionContext);

        await act.Should().NotThrowAsync();
    }
}
