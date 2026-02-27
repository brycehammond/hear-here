using HearHere.Shared.Data;
using HearHere.Shared.Services;
using Microsoft.Azure.Functions.Worker;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace HearHere.Functions.Functions;

public class CleanupAudioFunction
{
    private readonly HearHereDbContext _db;
    private readonly IBlobStorageService _blobStorage;

    public CleanupAudioFunction(HearHereDbContext db, IBlobStorageService blobStorage)
    {
        _db = db;
        _blobStorage = blobStorage;
    }

    /// <summary>
    /// Runs daily at 3 AM UTC. Finds recordings with status IN ('rejected', 'deleted')
    /// where updated_at is older than 30 days, deletes their blobs and DB records.
    /// </summary>
    [Function(nameof(CleanupOldAudio))]
    public async Task CleanupOldAudio(
        [TimerTrigger("0 0 3 * * *")] TimerInfo timerInfo,
        FunctionContext executionContext)
    {
        var logger = executionContext.GetLogger(nameof(CleanupOldAudio));
        logger.LogInformation("CleanupOldAudio timer fired at {Now}", DateTimeOffset.UtcNow);

        var cutoff = DateTimeOffset.UtcNow.AddDays(-30);
        var statuses = new[] { "rejected", "deleted" };

        var oldRecordings = await _db.Recordings
            .Where(r => statuses.Contains(r.Status) && r.UpdatedAt < cutoff)
            .ToListAsync();

        if (oldRecordings.Count == 0)
        {
            logger.LogInformation("No old recordings to clean up");
            return;
        }

        logger.LogInformation("Found {Count} old recordings to permanently delete", oldRecordings.Count);

        var deletedCount = 0;
        var errorCount = 0;

        foreach (var recording in oldRecordings)
        {
            try
            {
                // Delete the audio blob from Azure Blob Storage
                if (!string.IsNullOrEmpty(recording.AudioBlobKey))
                {
                    await _blobStorage.DeleteBlobAsync(recording.AudioBlobKey);
                    logger.LogInformation("Deleted blob {BlobKey} for recording {RecordingId}",
                        recording.AudioBlobKey, recording.Id);
                }

                // Remove the recording and related data from the database
                _db.Recordings.Remove(recording);
                deletedCount++;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Failed to clean up recording {RecordingId}", recording.Id);
                errorCount++;
            }
        }

        await _db.SaveChangesAsync();

        logger.LogInformation(
            "Audio cleanup complete: {DeletedCount} deleted, {ErrorCount} errors",
            deletedCount, errorCount);
    }
}
