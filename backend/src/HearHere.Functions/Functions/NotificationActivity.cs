using HearHere.Shared.Data;
using Microsoft.Azure.Functions.Worker;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace HearHere.Functions.Functions;

public class NotificationActivity
{
    private readonly HearHereDbContext _db;

    public NotificationActivity(HearHereDbContext db)
    {
        _db = db;
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

        var message = recording.Status switch
        {
            "approved" => $"Your recording '{recording.Subject}' is now live!",
            "rejected" => $"Your recording '{recording.Subject}' could not be approved.",
            "pending_review" => $"Your recording '{recording.Subject}' is under review.",
            _ => $"Your recording '{recording.Subject}' status updated to {recording.Status}."
        };

        // TODO: Integrate with Azure Notification Hubs / APNs
        // For now, log the notification that would be sent
        logger.LogInformation(
            "Push notification for user {UserId} ({DisplayName}): {Message}",
            recording.UserId,
            recording.User.DisplayName,
            message);
    }
}
