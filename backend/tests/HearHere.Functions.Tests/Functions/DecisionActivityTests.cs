using System.Text.Json;
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

public class DecisionActivityTests
{
    private readonly HearHereDbContext _db;
    private readonly DecisionActivity _sut;
    private readonly FunctionContext _functionContext;

    public DecisionActivityTests()
    {
        var options = new DbContextOptionsBuilder<HearHereDbContext>()
            .UseInMemoryDatabase(databaseName: $"DecisionTests_{Guid.NewGuid()}")
            .Options;
        _db = new HearHereDbContext(options);

        _sut = new DecisionActivity(_db);

        _functionContext = Substitute.For<FunctionContext>();
        var serviceProvider = Substitute.For<IServiceProvider>();
        _functionContext.InstanceServices.Returns(serviceProvider);

        var loggerFactory = Substitute.For<ILoggerFactory>();
        loggerFactory.CreateLogger(Arg.Any<string>()).Returns(Substitute.For<ILogger>());
        serviceProvider.GetService(typeof(ILoggerFactory)).Returns(loggerFactory);
    }

    [Fact]
    public async Task AllScoresBelowApproveThreshold_ReturnsAutoApprove()
    {
        var scores = new Dictionary<string, double>
        {
            ["hate"] = 0.1,
            ["harassment"] = 0.05,
            ["violence"] = 0.2,
            ["sexual"] = 0.1
        };

        var input = new EvaluateDecisionInput(
            Guid.NewGuid(),
            JsonSerializer.Serialize(scores));

        var result = await _sut.EvaluateDecision(input, _functionContext);

        result.Should().Be("AUTO_APPROVE");
    }

    [Fact]
    public async Task AnyScoreAboveRejectThreshold_ReturnsAutoReject()
    {
        var scores = new Dictionary<string, double>
        {
            ["hate"] = 0.1,
            ["harassment"] = 0.05,
            ["violence"] = 0.8,
            ["sexual"] = 0.1
        };

        var input = new EvaluateDecisionInput(
            Guid.NewGuid(),
            JsonSerializer.Serialize(scores));

        var result = await _sut.EvaluateDecision(input, _functionContext);

        result.Should().Be("AUTO_REJECT");
    }

    [Fact]
    public async Task ScoresInBetweenThresholds_ReturnsHumanReview()
    {
        var scores = new Dictionary<string, double>
        {
            ["hate"] = 0.1,
            ["harassment"] = 0.5,
            ["violence"] = 0.2,
            ["sexual"] = 0.1
        };

        var input = new EvaluateDecisionInput(
            Guid.NewGuid(),
            JsonSerializer.Serialize(scores));

        var result = await _sut.EvaluateDecision(input, _functionContext);

        result.Should().Be("HUMAN_REVIEW");
    }

    [Fact]
    public async Task ScoreExactlyAtApproveThreshold_ReturnsHumanReview()
    {
        // Score of exactly 0.3 means >= threshold, so allBelowApprove = false
        var scores = new Dictionary<string, double>
        {
            ["hate"] = 0.3,
            ["harassment"] = 0.1,
            ["violence"] = 0.1,
            ["sexual"] = 0.1
        };

        var input = new EvaluateDecisionInput(
            Guid.NewGuid(),
            JsonSerializer.Serialize(scores));

        var result = await _sut.EvaluateDecision(input, _functionContext);

        result.Should().Be("HUMAN_REVIEW");
    }

    [Fact]
    public async Task ScoreJustBelowApproveThreshold_ReturnsAutoApprove()
    {
        var scores = new Dictionary<string, double>
        {
            ["hate"] = 0.29,
            ["harassment"] = 0.29,
            ["violence"] = 0.29,
            ["sexual"] = 0.29
        };

        var input = new EvaluateDecisionInput(
            Guid.NewGuid(),
            JsonSerializer.Serialize(scores));

        var result = await _sut.EvaluateDecision(input, _functionContext);

        result.Should().Be("AUTO_APPROVE");
    }

    [Fact]
    public async Task HighRiskCategoryWithLowerThresholds_RejectsEarlier()
    {
        // "hate/threatening" has reject threshold of 0.5 (lower than default 0.7)
        var scores = new Dictionary<string, double>
        {
            ["hate/threatening"] = 0.6
        };

        var input = new EvaluateDecisionInput(
            Guid.NewGuid(),
            JsonSerializer.Serialize(scores));

        var result = await _sut.EvaluateDecision(input, _functionContext);

        result.Should().Be("AUTO_REJECT");
    }

    [Fact]
    public async Task HighRiskCategoryBelowItsApproveThreshold_AutoApproves()
    {
        // "hate/threatening" has approve threshold of 0.2
        var scores = new Dictionary<string, double>
        {
            ["hate/threatening"] = 0.1
        };

        var input = new EvaluateDecisionInput(
            Guid.NewGuid(),
            JsonSerializer.Serialize(scores));

        var result = await _sut.EvaluateDecision(input, _functionContext);

        result.Should().Be("AUTO_APPROVE");
    }

    [Fact]
    public async Task UnknownCategory_UsesDefaultThresholds()
    {
        // Unknown category uses default (0.3, 0.7) thresholds
        var scores = new Dictionary<string, double>
        {
            ["unknown_category"] = 0.5
        };

        var input = new EvaluateDecisionInput(
            Guid.NewGuid(),
            JsonSerializer.Serialize(scores));

        var result = await _sut.EvaluateDecision(input, _functionContext);

        result.Should().Be("HUMAN_REVIEW");
    }

    [Fact]
    public async Task ApplyDecision_AutoApprove_SetsStatusToApproved()
    {
        var recordingId = Guid.NewGuid();
        var recording = new Recording
        {
            Id = recordingId,
            UserId = Guid.NewGuid(),
            Subject = "Test",
            Status = "pending_moderation",
            AudioBlobKey = "test.aac",
            DurationSec = 60,
            Location = new NetTopologySuite.Geometries.Point(0, 0) { SRID = 4326 }
        };
        _db.Recordings.Add(recording);
        await _db.SaveChangesAsync();

        var input = new DecisionInput(recordingId, "AUTO_APPROVE", null);

        await _sut.ApplyDecision(input, _functionContext);

        var updated = await _db.Recordings.FindAsync(recordingId);
        updated!.Status.Should().Be("approved");

        var moderationRecord = await _db.ModerationRecords.FirstAsync(m => m.RecordingId == recordingId);
        moderationRecord.Action.Should().Be("auto_approve");
        moderationRecord.ActorType.Should().Be("system");
        moderationRecord.FromStatus.Should().Be("pending_moderation");
        moderationRecord.ToStatus.Should().Be("approved");
    }

    [Fact]
    public async Task ApplyDecision_AutoReject_SetsStatusToRejected()
    {
        var recordingId = Guid.NewGuid();
        var recording = new Recording
        {
            Id = recordingId,
            UserId = Guid.NewGuid(),
            Subject = "Test",
            Status = "pending_moderation",
            AudioBlobKey = "test.aac",
            DurationSec = 60,
            Location = new NetTopologySuite.Geometries.Point(0, 0) { SRID = 4326 }
        };
        _db.Recordings.Add(recording);
        await _db.SaveChangesAsync();

        var input = new DecisionInput(recordingId, "AUTO_REJECT", null);

        await _sut.ApplyDecision(input, _functionContext);

        var updated = await _db.Recordings.FindAsync(recordingId);
        updated!.Status.Should().Be("rejected");

        var moderationRecord = await _db.ModerationRecords.FirstAsync(m => m.RecordingId == recordingId);
        moderationRecord.Action.Should().Be("auto_reject");
    }

    [Fact]
    public async Task ApplyDecision_HumanReview_SetsStatusToPendingReview()
    {
        var recordingId = Guid.NewGuid();
        var recording = new Recording
        {
            Id = recordingId,
            UserId = Guid.NewGuid(),
            Subject = "Test",
            Status = "pending_moderation",
            AudioBlobKey = "test.aac",
            DurationSec = 60,
            Location = new NetTopologySuite.Geometries.Point(0, 0) { SRID = 4326 }
        };
        _db.Recordings.Add(recording);
        await _db.SaveChangesAsync();

        var input = new DecisionInput(recordingId, "HUMAN_REVIEW", "uncertain_score");

        await _sut.ApplyDecision(input, _functionContext);

        var updated = await _db.Recordings.FindAsync(recordingId);
        updated!.Status.Should().Be("pending_review");

        var moderationRecord = await _db.ModerationRecords.FirstAsync(m => m.RecordingId == recordingId);
        moderationRecord.Action.Should().Be("escalate_to_review");
        moderationRecord.Reason.Should().Be("uncertain_score");
    }

    [Fact]
    public async Task ApplyDecision_UnknownDecision_Throws()
    {
        var recordingId = Guid.NewGuid();
        var recording = new Recording
        {
            Id = recordingId,
            UserId = Guid.NewGuid(),
            Subject = "Test",
            Status = "pending_moderation",
            AudioBlobKey = "test.aac",
            DurationSec = 60,
            Location = new NetTopologySuite.Geometries.Point(0, 0) { SRID = 4326 }
        };
        _db.Recordings.Add(recording);
        await _db.SaveChangesAsync();

        var input = new DecisionInput(recordingId, "UNKNOWN", null);

        var act = () => _sut.ApplyDecision(input, _functionContext);

        await act.Should().ThrowAsync<InvalidOperationException>();
    }

    [Fact]
    public async Task ApplyHumanDecision_Approved_SetsStatusToApproved()
    {
        var recordingId = Guid.NewGuid();
        var recording = new Recording
        {
            Id = recordingId,
            UserId = Guid.NewGuid(),
            Subject = "Test",
            Status = "pending_review",
            AudioBlobKey = "test.aac",
            DurationSec = 60,
            Location = new NetTopologySuite.Geometries.Point(0, 0) { SRID = 4326 }
        };
        _db.Recordings.Add(recording);
        await _db.SaveChangesAsync();

        var input = new HumanDecisionInput(recordingId, "approved");

        await _sut.ApplyHumanDecision(input, _functionContext);

        var updated = await _db.Recordings.FindAsync(recordingId);
        updated!.Status.Should().Be("approved");

        var moderationRecord = await _db.ModerationRecords.FirstAsync(m => m.RecordingId == recordingId);
        moderationRecord.Action.Should().Be("manual_approve");
        moderationRecord.ActorType.Should().Be("moderator");
    }

    [Fact]
    public async Task ApplyHumanDecision_Rejected_SetsStatusToRejected()
    {
        var recordingId = Guid.NewGuid();
        var recording = new Recording
        {
            Id = recordingId,
            UserId = Guid.NewGuid(),
            Subject = "Test",
            Status = "pending_review",
            AudioBlobKey = "test.aac",
            DurationSec = 60,
            Location = new NetTopologySuite.Geometries.Point(0, 0) { SRID = 4326 }
        };
        _db.Recordings.Add(recording);
        await _db.SaveChangesAsync();

        var input = new HumanDecisionInput(recordingId, "rejected");

        await _sut.ApplyHumanDecision(input, _functionContext);

        var updated = await _db.Recordings.FindAsync(recordingId);
        updated!.Status.Should().Be("rejected");

        var moderationRecord = await _db.ModerationRecords.FirstAsync(m => m.RecordingId == recordingId);
        moderationRecord.Action.Should().Be("manual_reject");
    }
}
