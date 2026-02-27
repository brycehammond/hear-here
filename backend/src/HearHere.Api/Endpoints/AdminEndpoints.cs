using System.Text;
using System.Text.Json;
using FluentValidation;
using HearHere.Api.Auth;
using HearHere.Shared.Data;
using HearHere.Shared.Data.Entities;
using HearHere.Shared.Exceptions;
using HearHere.Shared.Models.Requests;
using HearHere.Shared.Models.Responses;
using HearHere.Shared.Services;
using Microsoft.EntityFrameworkCore;

namespace HearHere.Api.Endpoints;

public static class AdminEndpoints
{
    public static RouteGroupBuilder MapAdminEndpoints(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/v1/admin/moderation")
            .RequireAuthorization("AdminOnly")
            .WithTags("Admin");

        group.MapGet("/queue", GetQueue)
            .WithName("GetModerationQueue")
            .WithSummary("Get the moderation review queue")
            .Produces<PaginatedResponse<ModerationQueueItemResponse>>();

        group.MapPost("/{recordingId:guid}/decision", PostDecision)
            .WithName("PostModerationDecision")
            .WithSummary("Submit a moderation decision for a recording")
            .Produces<ModerationDecisionResponse>();

        group.MapGet("/stats", GetStats)
            .WithName("GetModerationStats")
            .WithSummary("Get moderation statistics")
            .Produces<ModerationStatsResponse>();

        return group;
    }

    private static async Task<IResult> GetQueue(
        HearHereDbContext db,
        IBlobStorageService blobStorage,
        string? cursor = null,
        int limit = 20)
    {
        limit = Math.Clamp(limit, 1, 50);

        var query = db.Recordings
            .Include(r => r.User)
            .Where(r => r.Status == "pending_review" && r.DeletedAt == null);

        // Cursor pagination using (created_at, id)
        if (!string.IsNullOrEmpty(cursor))
        {
            var cursorData = DecodeCursor(cursor);
            if (cursorData is not null)
            {
                var cursorDate = cursorData.Value.CreatedAt;
                var cursorId = cursorData.Value.Id;
                query = query.Where(r =>
                    r.CreatedAt > cursorDate ||
                    (r.CreatedAt == cursorDate && r.Id.CompareTo(cursorId) > 0));
            }
        }

        var recordings = await query
            .OrderBy(r => r.CreatedAt)
            .ThenBy(r => r.Id)
            .Take(limit + 1)
            .ToListAsync();

        var items = new List<ModerationQueueItemResponse>();
        foreach (var r in recordings.Take(limit))
        {
            string? playbackUrl = null;
            try
            {
                var (url, _) = await blobStorage.GenerateReadSasUrl(r.AudioBlobKey, TimeSpan.FromHours(1));
                playbackUrl = url.ToString();
            }
            catch
            {
                // Blob may not exist for some edge cases
            }

            var reportCount = await db.Reports.CountAsync(rep => rep.RecordingId == r.Id);

            items.Add(new ModerationQueueItemResponse
            {
                Id = r.Id,
                Subject = r.Subject,
                Description = r.Description,
                DurationSec = r.DurationSec,
                Transcript = r.Transcript,
                ModerationResult = r.ModerationScores is not null
                    ? JsonSerializer.Deserialize<object>(r.ModerationScores)
                    : null,
                ReportCount = reportCount,
                PlaybackUrl = playbackUrl,
                CreatedAt = r.CreatedAt,
                User = new ModerationQueueUserResponse
                {
                    Id = r.User.Id.ToString(),
                    DisplayName = r.User.DisplayName
                }
            });
        }

        string? nextCursor = null;
        if (recordings.Count > limit)
        {
            var last = recordings[limit - 1];
            nextCursor = EncodeCursor(last.CreatedAt, last.Id);
        }

        return Results.Ok(new PaginatedResponse<ModerationQueueItemResponse>
        {
            Items = items,
            NextCursor = nextCursor
        });
    }

    private static async Task<IResult> PostDecision(
        Guid recordingId,
        ModerationDecisionRequest request,
        IValidator<ModerationDecisionRequest> validator,
        HearHereDbContext db,
        HttpContext httpContext)
    {
        await validator.ValidateAndThrowAsync(request);

        var user = await httpContext.GetRequiredUserAsync(db);

        var recording = await db.Recordings
            .FirstOrDefaultAsync(r => r.Id == recordingId && r.DeletedAt == null);

        if (recording is null)
            throw new NotFoundException("Recording not found.");

        if (recording.Status != "pending_review")
            throw new ConflictException("Recording is not in pending_review status.");

        var fromStatus = recording.Status;
        var toStatus = request.Decision == "approved" ? "approved" : "rejected";

        recording.Status = toStatus;
        recording.UpdatedAt = DateTimeOffset.UtcNow;

        var moderationRecord = new ModerationRecord
        {
            RecordingId = recordingId,
            Action = request.Decision == "approved" ? "manual_approve" : "manual_reject",
            ActorType = "admin",
            ActorId = user.Id.ToString(),
            FromStatus = fromStatus,
            ToStatus = toStatus,
            Reason = request.Notes
        };

        db.ModerationRecords.Add(moderationRecord);
        await db.SaveChangesAsync();

        return Results.Ok(new ModerationDecisionResponse
        {
            Id = recording.Id,
            Status = recording.Status,
            ReviewedBy = user.Id.ToString(),
            ReviewedAt = moderationRecord.CreatedAt
        });
    }

    private static async Task<IResult> GetStats(HearHereDbContext db)
    {
        var today = DateTimeOffset.UtcNow.Date;

        var pendingReview = await db.Recordings
            .CountAsync(r => r.Status == "pending_review" && r.DeletedAt == null);

        var reviewedToday = await db.ModerationRecords
            .CountAsync(m => m.CreatedAt >= today
                && (m.Action == "manual_approve" || m.Action == "manual_reject"));

        var autoApprovedToday = await db.ModerationRecords
            .CountAsync(m => m.CreatedAt >= today && m.Action == "auto_approve");

        var autoRejectedToday = await db.ModerationRecords
            .CountAsync(m => m.CreatedAt >= today && m.Action == "auto_reject");

        // Calculate average review time for manual reviews today
        // Time between recording creation and moderation record creation
        var avgReviewTimeSec = await db.ModerationRecords
            .Where(m => m.CreatedAt >= today
                && (m.Action == "manual_approve" || m.Action == "manual_reject"))
            .Join(db.Recordings, m => m.RecordingId, r => r.Id, (m, r) => new { m, r })
            .Select(x => (x.m.CreatedAt - x.r.CreatedAt).TotalSeconds)
            .DefaultIfEmpty(0)
            .AverageAsync();

        return Results.Ok(new ModerationStatsResponse
        {
            PendingReview = pendingReview,
            ReviewedToday = reviewedToday,
            AutoApprovedToday = autoApprovedToday,
            AutoRejectedToday = autoRejectedToday,
            AvgReviewTimeSec = Math.Round(avgReviewTimeSec, 1)
        });
    }

    private static string EncodeCursor(DateTimeOffset createdAt, Guid id)
    {
        var json = JsonSerializer.Serialize(new { created_at = createdAt, id });
        return Convert.ToBase64String(Encoding.UTF8.GetBytes(json));
    }

    private static (DateTimeOffset CreatedAt, Guid Id)? DecodeCursor(string cursor)
    {
        try
        {
            var json = Encoding.UTF8.GetString(Convert.FromBase64String(cursor));
            var doc = JsonDocument.Parse(json);
            var createdAt = doc.RootElement.GetProperty("created_at").GetDateTimeOffset();
            var id = doc.RootElement.GetProperty("id").GetGuid();
            return (createdAt, id);
        }
        catch
        {
            return null;
        }
    }
}
