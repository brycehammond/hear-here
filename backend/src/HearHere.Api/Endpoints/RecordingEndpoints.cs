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
using NetTopologySuite.Geometries;

namespace HearHere.Api.Endpoints;

public static class RecordingEndpoints
{
    private const int DailyUploadLimit = 10;

    public static RouteGroupBuilder MapRecordingEndpoints(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/v1/recordings")
            .RequireAuthorization()
            .WithTags("Recordings");

        group.MapPost("/", Create)
            .WithName("CreateRecording")
            .WithSummary("Create a new recording")
            .Produces<RecordingCreateResponse>(StatusCodes.Status201Created);

        group.MapGet("/mine", Mine)
            .WithName("GetMyRecordings")
            .WithSummary("List current user's recordings")
            .Produces<PaginatedResponse<RecordingResponse>>();

        group.MapGet("/{id:guid}", GetById)
            .WithName("GetRecording")
            .WithSummary("Get a recording by ID")
            .Produces<RecordingResponse>();

        group.MapDelete("/{id:guid}", Delete)
            .WithName("DeleteRecording")
            .WithSummary("Delete a recording")
            .Produces(StatusCodes.Status204NoContent);

        group.MapPost("/{id:guid}/upload-complete", UploadComplete)
            .WithName("UploadComplete")
            .WithSummary("Mark recording upload as complete")
            .Produces<UploadCompleteResponse>();

        group.MapGet("/{id:guid}/playback", Playback)
            .WithName("GetPlayback")
            .WithSummary("Get playback URL for a recording")
            .Produces<PlaybackResponse>();

        return group;
    }

    private static async Task<IResult> Create(
        CreateRecordingRequest request,
        IValidator<CreateRecordingRequest> validator,
        HearHereDbContext db,
        IBlobStorageService blobStorage,
        HttpContext httpContext)
    {
        await validator.ValidateAndThrowAsync(request);

        var user = await httpContext.GetRequiredUserAsync(db);

        // Check daily upload limit
        var todayStart = DateTimeOffset.UtcNow.Date;
        var todayCount = await db.Recordings
            .CountAsync(r => r.UserId == user.Id && r.CreatedAt >= todayStart);

        if (todayCount >= DailyUploadLimit)
        {
            return Results.Json(new ErrorResponse
            {
                Error = new ErrorDetail
                {
                    Code = "DAILY_UPLOAD_LIMIT",
                    Message = $"You have reached the daily upload limit of {DailyUploadLimit} recordings."
                }
            }, statusCode: StatusCodes.Status429TooManyRequests);
        }

        var recording = new Recording
        {
            UserId = user.Id,
            Subject = request.Subject,
            Description = request.Description,
            Location = new Point(request.Longitude, request.Latitude) { SRID = 4326 },
            DurationSec = request.DurationSec,
            Status = "pending_upload",
            AudioBlobKey = $"recordings/{Guid.NewGuid():N}.aac"
        };

        db.Recordings.Add(recording);
        await db.SaveChangesAsync();

        var (uploadUrl, expiresAt) = await blobStorage.GenerateUploadSasUrl(
            recording.AudioBlobKey,
            TimeSpan.FromMinutes(15));

        return Results.Created($"/v1/recordings/{recording.Id}", new RecordingCreateResponse
        {
            Id = recording.Id,
            UploadUrl = uploadUrl.ToString(),
            UploadExpiresAt = expiresAt,
            Status = "pending_upload"
        });
    }

    private static async Task<IResult> GetById(
        Guid id,
        HearHereDbContext db,
        HttpContext httpContext)
    {
        var user = await httpContext.GetRequiredUserAsync(db);

        var recording = await db.Recordings
            .Include(r => r.User)
            .FirstOrDefaultAsync(r => r.Id == id && r.DeletedAt == null);

        if (recording is null)
            throw new NotFoundException("Recording not found.");

        // Owner can see any status; others can only see approved
        if (recording.UserId != user.Id && recording.Status != "approved")
            throw new NotFoundException("Recording not found.");

        return Results.Ok(new RecordingResponse
        {
            Id = recording.Id,
            UserId = recording.UserId.ToString(),
            DisplayName = recording.User.DisplayName,
            Subject = recording.Subject,
            Description = recording.Description,
            Latitude = recording.Location.Y,
            Longitude = recording.Location.X,
            DurationSec = recording.DurationSec,
            Status = recording.Status,
            CreatedAt = recording.CreatedAt
        });
    }

    private static async Task<IResult> Delete(
        Guid id,
        HearHereDbContext db,
        HttpContext httpContext)
    {
        var user = await httpContext.GetRequiredUserAsync(db);

        var recording = await db.Recordings
            .FirstOrDefaultAsync(r => r.Id == id && r.DeletedAt == null && r.UserId == user.Id);

        if (recording is null)
            throw new NotFoundException("Recording not found.");

        recording.DeletedAt = DateTimeOffset.UtcNow;
        recording.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync();

        return Results.NoContent();
    }

    private static async Task<IResult> Mine(
        HearHereDbContext db,
        HttpContext httpContext,
        string? status = null,
        string? cursor = null,
        int limit = 20)
    {
        var user = await httpContext.GetRequiredUserAsync(db);

        limit = Math.Clamp(limit, 1, 50);

        var query = db.Recordings
            .Where(r => r.UserId == user.Id && r.DeletedAt == null);

        if (!string.IsNullOrEmpty(status))
            query = query.Where(r => r.Status == status);

        // Cursor-based pagination using (created_at, id)
        if (!string.IsNullOrEmpty(cursor))
        {
            var cursorData = DecodeCursor(cursor);
            if (cursorData is not null)
            {
                var cursorDate = cursorData.Value.CreatedAt;
                var cursorId = cursorData.Value.Id;
                query = query.Where(r =>
                    r.CreatedAt < cursorDate ||
                    (r.CreatedAt == cursorDate && r.Id.CompareTo(cursorId) < 0));
            }
        }

        var recordings = await query
            .OrderByDescending(r => r.CreatedAt)
            .ThenByDescending(r => r.Id)
            .Take(limit + 1)
            .Select(r => new RecordingResponse
            {
                Id = r.Id,
                UserId = r.UserId.ToString(),
                DisplayName = r.User.DisplayName,
                Subject = r.Subject,
                Description = r.Description,
                Latitude = r.Location.Y,
                Longitude = r.Location.X,
                DurationSec = r.DurationSec,
                Status = r.Status,
                CreatedAt = r.CreatedAt
            })
            .ToListAsync();

        string? nextCursor = null;
        if (recordings.Count > limit)
        {
            recordings.RemoveAt(recordings.Count - 1);
            var last = recordings[^1];
            nextCursor = EncodeCursor(last.CreatedAt, last.Id);
        }

        return Results.Ok(new PaginatedResponse<RecordingResponse>
        {
            Items = recordings,
            NextCursor = nextCursor
        });
    }

    private static async Task<IResult> UploadComplete(
        Guid id,
        HearHereDbContext db,
        IBlobStorageService blobStorage,
        IMessageQueueService messageQueue,
        HttpContext httpContext)
    {
        var user = await httpContext.GetRequiredUserAsync(db);

        var recording = await db.Recordings
            .FirstOrDefaultAsync(r => r.Id == id && r.UserId == user.Id && r.DeletedAt == null);

        if (recording is null)
            throw new NotFoundException("Recording not found.");

        if (recording.Status != "pending_upload")
            throw new ConflictException("Recording is not in pending_upload status.");

        // Verify blob exists
        var exists = await blobStorage.BlobExistsAsync(recording.AudioBlobKey);
        if (!exists)
            throw new ConflictException("Audio file has not been uploaded yet.");

        recording.Status = "pending_moderation";
        recording.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync();

        // Send message to Service Bus to start moderation pipeline
        await messageQueue.SendModerationRequestAsync(recording.Id);

        return Results.Ok(new UploadCompleteResponse { Id = recording.Id, Status = recording.Status });
    }

    private static async Task<IResult> Playback(
        Guid id,
        HearHereDbContext db,
        IBlobStorageService blobStorage,
        HttpContext httpContext)
    {
        var user = await httpContext.GetRequiredUserAsync(db);

        var recording = await db.Recordings
            .FirstOrDefaultAsync(r => r.Id == id && r.DeletedAt == null);

        if (recording is null)
            throw new NotFoundException("Recording not found.");

        // Only approved recordings or owner's own are playable
        if (recording.Status != "approved" && recording.UserId != user.Id)
            throw new ForbiddenException("Recording is not playable.");

        var (url, expiresAt) = await blobStorage.GenerateReadSasUrl(
            recording.AudioBlobKey,
            TimeSpan.FromHours(1));

        return Results.Ok(new PlaybackResponse
        {
            PlaybackUrl = url.ToString(),
            ExpiresAt = expiresAt,
            DurationSec = recording.DurationSec,
            Format = recording.AudioFormat
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
