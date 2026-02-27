using HearHere.Shared.Data;
using HearHere.Shared.Data.Entities;
using Microsoft.Azure.Functions.Worker;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace HearHere.Functions.Functions;

public class CleanupUploadsFunction
{
    private readonly HearHereDbContext _db;

    public CleanupUploadsFunction(HearHereDbContext db)
    {
        _db = db;
    }

    /// <summary>
    /// Runs every hour. Finds recordings with status='pending_upload' older than 1 hour
    /// and marks them as expired (rejected).
    /// </summary>
    [Function(nameof(CleanupStaleUploads))]
    public async Task CleanupStaleUploads(
        [TimerTrigger("0 0 * * * *")] TimerInfo timerInfo,
        FunctionContext executionContext)
    {
        var logger = executionContext.GetLogger(nameof(CleanupStaleUploads));
        logger.LogInformation("CleanupStaleUploads timer fired at {Now}", DateTimeOffset.UtcNow);

        var cutoff = DateTimeOffset.UtcNow.AddHours(-1);

        var staleRecordings = await _db.Recordings
            .Where(r => r.Status == "pending_upload" && r.CreatedAt < cutoff)
            .ToListAsync();

        if (staleRecordings.Count == 0)
        {
            logger.LogInformation("No stale uploads found");
            return;
        }

        logger.LogInformation("Found {Count} stale uploads to expire", staleRecordings.Count);

        foreach (var recording in staleRecordings)
        {
            var fromStatus = recording.Status;
            recording.Status = "rejected";
            recording.UpdatedAt = DateTimeOffset.UtcNow;
            recording.DeletedAt = DateTimeOffset.UtcNow;

            var moderationRecord = new ModerationRecord
            {
                Id = Guid.NewGuid(),
                RecordingId = recording.Id,
                Action = "auto_reject",
                ActorType = "system",
                FromStatus = fromStatus,
                ToStatus = "rejected",
                Reason = "Upload expired: pending_upload older than 1 hour",
                CreatedAt = DateTimeOffset.UtcNow
            };

            _db.ModerationRecords.Add(moderationRecord);
        }

        await _db.SaveChangesAsync();

        logger.LogInformation("Expired {Count} stale uploads", staleRecordings.Count);
    }
}
