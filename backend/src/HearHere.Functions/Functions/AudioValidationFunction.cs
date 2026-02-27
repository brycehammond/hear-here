using Azure.Messaging.EventGrid;
using HearHere.Shared.Data;
using HearHere.Shared.Data.Entities;
using HearHere.Shared.Services;
using Microsoft.Azure.Functions.Worker;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace HearHere.Functions.Functions;

public class AudioValidationFunction
{
    private readonly HearHereDbContext _db;
    private readonly IBlobStorageService _blobStorage;
    private const long MaxFileSizeBytes = 10 * 1024 * 1024; // 10MB
    private const int MaxDurationDifferenceSeconds = 5;
    private const int HeaderCheckSize = 12;
    private const int DurationCheckSize = 256 * 1024; // 256KB

    public AudioValidationFunction(HearHereDbContext db, IBlobStorageService blobStorage)
    {
        _db = db;
        _blobStorage = blobStorage;
    }

    [Function(nameof(ValidateAudio))]
    public async Task ValidateAudio(
        [EventGridTrigger] EventGridEvent eventGridEvent,
        FunctionContext executionContext)
    {
        var logger = executionContext.GetLogger(nameof(ValidateAudio));

        // Extract blob name from subject (e.g., "/blobServices/default/containers/recordings/blobs/recordings/abc.aac")
        var subject = eventGridEvent.Subject;
        var blobName = ExtractBlobName(subject);

        logger.LogInformation("Validating audio blob: {BlobName}", blobName);

        // Look up recording by AudioBlobKey
        var recording = await _db.Recordings
            .FirstOrDefaultAsync(r => r.AudioBlobKey == blobName && r.DeletedAt == null);

        if (recording == null)
        {
            logger.LogWarning("No recording found for blob {BlobName}, skipping validation", blobName);
            return;
        }

        // Size check
        var properties = await _blobStorage.GetBlobPropertiesAsync(blobName);
        if (properties == null)
        {
            logger.LogWarning("Blob {BlobName} not found for size check", blobName);
            return;
        }

        if (properties.ContentLength > MaxFileSizeBytes)
        {
            await RejectRecording(recording, $"File size {properties.ContentLength} bytes exceeds maximum of {MaxFileSizeBytes} bytes");
            logger.LogInformation("Recording {RecordingId} rejected: file too large", recording.Id);
            return;
        }

        // Header check - download first 12 bytes
        var headerBytes = await _blobStorage.DownloadBlobRangeAsync(blobName, 0, HeaderCheckSize);
        if (!IsValidAudioHeader(headerBytes))
        {
            await RejectRecording(recording, "Invalid audio format: not a recognized AAC/M4A/MP4 file");
            logger.LogInformation("Recording {RecordingId} rejected: invalid audio header", recording.Id);
            return;
        }

        // Duration check - download first 256KB and try to parse mvhd atom
        try
        {
            var durationCheckBytes = await _blobStorage.DownloadBlobRangeAsync(blobName, 0, DurationCheckSize);
            var parsedDuration = TryParseMvhdDuration(durationCheckBytes);

            if (parsedDuration.HasValue)
            {
                var difference = Math.Abs(parsedDuration.Value - recording.DurationSec);
                if (difference > MaxDurationDifferenceSeconds)
                {
                    await RejectRecording(recording,
                        $"Duration mismatch: declared {recording.DurationSec}s, actual {parsedDuration.Value:F1}s (difference {difference:F1}s exceeds {MaxDurationDifferenceSeconds}s tolerance)");
                    logger.LogInformation("Recording {RecordingId} rejected: duration mismatch", recording.Id);
                    return;
                }
            }
            else
            {
                logger.LogWarning("Could not parse mvhd atom for recording {RecordingId}, skipping duration check", recording.Id);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Duration check failed for recording {RecordingId}, skipping", recording.Id);
        }

        logger.LogInformation("Recording {RecordingId} passed audio validation", recording.Id);
    }

    public static string ExtractBlobName(string subject)
    {
        // Subject format: /blobServices/default/containers/{container}/blobs/{blobName}
        const string blobsSegment = "/blobs/";
        var index = subject.IndexOf(blobsSegment, StringComparison.OrdinalIgnoreCase);
        return index >= 0 ? subject[(index + blobsSegment.Length)..] : subject;
    }

    public static bool IsValidAudioHeader(byte[] header)
    {
        if (header.Length < 4)
            return false;

        // Check for AAC ADTS sync word: first 12 bits should be 0xFFF
        if (header.Length >= 2)
        {
            if (header[0] == 0xFF && (header[1] & 0xF0) == 0xF0)
                return true;
        }

        // Check for M4A/MP4: "ftyp" at bytes 4-7
        if (header.Length >= 8)
        {
            if (header[4] == 'f' && header[5] == 't' && header[6] == 'y' && header[7] == 'p')
                return true;
        }

        return false;
    }

    public static double? TryParseMvhdDuration(byte[] data)
    {
        // Search for 'mvhd' atom in the data
        for (int i = 0; i < data.Length - 8; i++)
        {
            if (data[i] == 'm' && data[i + 1] == 'v' && data[i + 2] == 'h' && data[i + 3] == 'd')
            {
                // Found mvhd atom
                var version = data[i + 4];

                if (version == 0)
                {
                    // Version 0: timescale at offset 12, duration at offset 16 (both 4 bytes)
                    if (i + 20 > data.Length) return null;

                    var timescale = (uint)((data[i + 12] << 24) | (data[i + 13] << 16) | (data[i + 14] << 8) | data[i + 15]);
                    var duration = (uint)((data[i + 16] << 24) | (data[i + 17] << 16) | (data[i + 18] << 8) | data[i + 19]);

                    if (timescale == 0) return null;
                    return (double)duration / timescale;
                }
                else if (version == 1)
                {
                    // Version 1: timescale at offset 20, duration at offset 24 (both 8 bytes for duration, 4 for timescale)
                    if (i + 32 > data.Length) return null;

                    var timescale = (uint)((data[i + 20] << 24) | (data[i + 21] << 16) | (data[i + 22] << 8) | data[i + 23]);
                    var duration = ((long)data[i + 24] << 56) | ((long)data[i + 25] << 48) | ((long)data[i + 26] << 40) | ((long)data[i + 27] << 32)
                                 | ((long)data[i + 28] << 24) | ((long)data[i + 29] << 16) | ((long)data[i + 30] << 8) | data[i + 31];

                    if (timescale == 0) return null;
                    return (double)duration / timescale;
                }
            }
        }

        return null; // mvhd not found
    }

    private async Task RejectRecording(Recording recording, string reason)
    {
        var fromStatus = recording.Status;
        recording.Status = "rejected";
        recording.UpdatedAt = DateTimeOffset.UtcNow;

        var moderationRecord = new ModerationRecord
        {
            Id = Guid.NewGuid(),
            RecordingId = recording.Id,
            Action = "auto_reject",
            ActorType = "system",
            FromStatus = fromStatus,
            ToStatus = "rejected",
            Reason = reason,
            CreatedAt = DateTimeOffset.UtcNow
        };

        _db.ModerationRecords.Add(moderationRecord);
        await _db.SaveChangesAsync();
    }
}
