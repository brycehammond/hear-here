using FluentValidation;
using HearHere.Api.Auth;
using HearHere.Shared.Data;
using HearHere.Shared.Data.Entities;
using HearHere.Shared.Exceptions;
using HearHere.Shared.Models.Requests;
using HearHere.Shared.Models.Responses;
using Microsoft.EntityFrameworkCore;

namespace HearHere.Api.Endpoints;

public static class ReportEndpoints
{
    private const int AutoEscalateThreshold = 3;

    public static RouteGroupBuilder MapReportEndpoints(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/v1/reports").RequireAuthorization();

        group.MapPost("/", CreateReport);

        return group;
    }

    private static async Task<IResult> CreateReport(
        CreateReportRequest request,
        IValidator<CreateReportRequest> validator,
        HearHereDbContext db,
        HttpContext httpContext)
    {
        await validator.ValidateAndThrowAsync(request);

        var user = await httpContext.GetRequiredUserAsync(db);

        var recording = await db.Recordings
            .FirstOrDefaultAsync(r => r.Id == request.RecordingId && r.DeletedAt == null);

        if (recording is null)
            throw new NotFoundException("Recording not found.");

        // Cannot report own recordings
        if (recording.UserId == user.Id)
            throw new ForbiddenException("You cannot report your own recording.");

        // Check for duplicate report
        var existingReport = await db.Reports
            .AnyAsync(r => r.RecordingId == request.RecordingId && r.UserId == user.Id);

        if (existingReport)
            throw new ConflictException("You have already reported this recording.");

        var report = new Report
        {
            RecordingId = request.RecordingId,
            UserId = user.Id,
            ReasonCode = request.Reason,
            Description = request.Description
        };

        db.Reports.Add(report);
        await db.SaveChangesAsync();

        // Check if recording should be auto-escalated
        var distinctReporterCount = await db.Reports
            .Where(r => r.RecordingId == request.RecordingId)
            .Select(r => r.UserId)
            .Distinct()
            .CountAsync();

        if (distinctReporterCount >= AutoEscalateThreshold && recording.Status == "approved")
        {
            recording.Status = "pending_review";
            recording.UpdatedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync();
        }

        return Results.Created($"/v1/reports/{report.Id}", new ReportResponse
        {
            Id = report.Id,
            RecordingId = report.RecordingId,
            Status = report.Status,
            CreatedAt = report.CreatedAt
        });
    }
}
