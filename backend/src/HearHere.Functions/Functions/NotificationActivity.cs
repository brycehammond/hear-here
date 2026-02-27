using HearHere.Shared.Data;
using HearHere.Shared.Services;
using Microsoft.Azure.Functions.Worker;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace HearHere.Functions.Functions;

public class NotificationActivity
{
    private readonly HearHereDbContext _db;
    private readonly INotificationService _notificationService;

    public NotificationActivity(HearHereDbContext db, INotificationService notificationService)
    {
        _db = db;
        _notificationService = notificationService;
    }

    [Function(nameof(SendNotification))]
    public async Task SendNotification(
        [ActivityTrigger] Guid recordingId,
        FunctionContext executionContext)
    {
        var logger = executionContext.GetLogger(nameof(SendNotification));

        var recording = await _db.Recordings
            .Include(r => r.User)
            .FirstOrDefaultAsync(r => r.Id == recordingId);

        if (recording == null)
        {
            logger.LogWarning("Recording {RecordingId} not found for notification", recordingId);
            return;
        }

        var (title, body) = recording.Status switch
        {
            "approved" => ("Recording Approved", $"Your recording '{recording.Subject}' is now live!"),
            "rejected" => ("Recording Not Approved", $"Your recording '{recording.Subject}' could not be approved."),
            "pending_review" => ("Recording Under Review", $"Your recording '{recording.Subject}' is under review."),
            _ => ("Recording Update", $"Your recording '{recording.Subject}' status updated to {recording.Status}.")
        };

        if (string.IsNullOrEmpty(recording.User.ApnsToken))
        {
            logger.LogInformation(
                "No APNs token for user {UserId}, skipping push notification for recording {RecordingId}",
                recording.UserId, recordingId);
            return;
        }

        try
        {
            await _notificationService.SendPushNotificationAsync(
                recording.User.ApnsToken,
                title,
                body,
                new Dictionary<string, string>
                {
                    ["recording_id"] = recordingId.ToString(),
                    ["status"] = recording.Status
                });

            logger.LogInformation(
                "Push notification sent to user {UserId} for recording {RecordingId}: {Title}",
                recording.UserId, recordingId, title);
        }
        catch (Exception ex)
        {
            logger.LogError(ex,
                "Failed to send push notification to user {UserId} for recording {RecordingId}",
                recording.UserId, recordingId);
        }
    }
}
