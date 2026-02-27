using System.Text.Json;
using HearHere.Shared.Configuration;
using HearHere.Shared.Data;
using HearHere.Shared.Data.Entities;
using Microsoft.Azure.Functions.Worker;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace HearHere.Functions.Functions;

public class DecisionActivity
{
    private readonly HearHereDbContext _db;
    private readonly ModerationSettings _settings;

    public DecisionActivity(HearHereDbContext db, IOptions<ModerationSettings> settings)
    {
        _db = db;
        _settings = settings.Value;
    }

    [Function(nameof(EvaluateDecision))]
    public Task<string> EvaluateDecision(
        [ActivityTrigger] EvaluateDecisionInput input,
        FunctionContext executionContext)
    {
        var logger = executionContext.GetLogger(nameof(EvaluateDecision));
        logger.LogInformation("Evaluating decision for recording {RecordingId}", input.RecordingId);

        var scores = JsonSerializer.Deserialize<Dictionary<string, double>>(input.ModerationScoresJson)
            ?? throw new InvalidOperationException("Failed to parse moderation scores");

        var anyAboveReject = false;
        var allBelowApprove = true;

        foreach (var (category, score) in scores)
        {
            if (!_settings.Thresholds.TryGetValue(category, out var threshold))
            {
                threshold = _settings.DefaultThreshold;
            }

            if (score > threshold.RejectAbove)
            {
                anyAboveReject = true;
                break;
            }

            if (score >= threshold.ApproveBelow)
            {
                allBelowApprove = false;
            }
        }

        string decision;
        if (anyAboveReject)
        {
            decision = "AUTO_REJECT";
        }
        else if (allBelowApprove)
        {
            decision = "AUTO_APPROVE";
        }
        else
        {
            decision = "HUMAN_REVIEW";
        }

        logger.LogInformation("Decision for recording {RecordingId}: {Decision}", input.RecordingId, decision);
        return Task.FromResult(decision);
    }

    [Function(nameof(ApplyDecision))]
    public async Task ApplyDecision(
        [ActivityTrigger] DecisionInput input,
        FunctionContext executionContext)
    {
        var logger = executionContext.GetLogger(nameof(ApplyDecision));
        logger.LogInformation("Applying decision {Decision} for recording {RecordingId}",
            input.Decision, input.RecordingId);

        var recording = await _db.Recordings.FirstOrDefaultAsync(r => r.Id == input.RecordingId)
            ?? throw new InvalidOperationException($"Recording {input.RecordingId} not found");

        var fromStatus = recording.Status;

        string toStatus;
        string action;
        switch (input.Decision)
        {
            case "AUTO_APPROVE":
                toStatus = "approved";
                action = "auto_approve";
                break;
            case "AUTO_REJECT":
                toStatus = "rejected";
                action = "auto_reject";
                break;
            case "HUMAN_REVIEW":
                toStatus = "pending_review";
                action = "escalate_to_review";
                break;
            default:
                throw new InvalidOperationException($"Unknown decision: {input.Decision}");
        }

        recording.Status = toStatus;
        recording.UpdatedAt = DateTimeOffset.UtcNow;

        var moderationRecord = new ModerationRecord
        {
            Id = Guid.NewGuid(),
            RecordingId = input.RecordingId,
            Action = action,
            ActorType = "system",
            FromStatus = fromStatus,
            ToStatus = toStatus,
            Scores = recording.ModerationScores,
            Reason = input.Reason,
            CreatedAt = DateTimeOffset.UtcNow
        };

        _db.ModerationRecords.Add(moderationRecord);
        await _db.SaveChangesAsync();

        logger.LogInformation("Recording {RecordingId} status changed from {FromStatus} to {ToStatus}",
            input.RecordingId, fromStatus, toStatus);
    }

    [Function(nameof(ApplyHumanDecision))]
    public async Task ApplyHumanDecision(
        [ActivityTrigger] HumanDecisionInput input,
        FunctionContext executionContext)
    {
        var logger = executionContext.GetLogger(nameof(ApplyHumanDecision));
        logger.LogInformation("Applying human decision {Decision} for recording {RecordingId}",
            input.Decision, input.RecordingId);

        var recording = await _db.Recordings.FirstOrDefaultAsync(r => r.Id == input.RecordingId)
            ?? throw new InvalidOperationException($"Recording {input.RecordingId} not found");

        var fromStatus = recording.Status;
        string toStatus;
        string action;

        switch (input.Decision.ToLowerInvariant())
        {
            case "approved":
                toStatus = "approved";
                action = "manual_approve";
                break;
            case "rejected":
                toStatus = "rejected";
                action = "manual_reject";
                break;
            default:
                throw new InvalidOperationException($"Unknown human decision: {input.Decision}");
        }

        recording.Status = toStatus;
        recording.UpdatedAt = DateTimeOffset.UtcNow;

        var moderationRecord = new ModerationRecord
        {
            Id = Guid.NewGuid(),
            RecordingId = input.RecordingId,
            Action = action,
            ActorType = "moderator",
            FromStatus = fromStatus,
            ToStatus = toStatus,
            Reason = "Human review decision",
            CreatedAt = DateTimeOffset.UtcNow
        };

        _db.ModerationRecords.Add(moderationRecord);
        await _db.SaveChangesAsync();

        logger.LogInformation("Human decision applied for recording {RecordingId}: {FromStatus} -> {ToStatus}",
            input.RecordingId, fromStatus, toStatus);
    }
}
