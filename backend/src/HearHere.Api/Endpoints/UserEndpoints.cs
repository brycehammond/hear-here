using FluentValidation;
using HearHere.Api.Auth;
using HearHere.Shared.Data;
using HearHere.Shared.Models.Requests;
using HearHere.Shared.Models.Responses;
using Microsoft.EntityFrameworkCore;

namespace HearHere.Api.Endpoints;

public static class UserEndpoints
{
    public static RouteGroupBuilder MapUserEndpoints(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/v1/users")
            .RequireAuthorization()
            .WithTags("Users");

        group.MapGet("/me", GetMe)
            .WithName("GetMe")
            .WithSummary("Get current user profile")
            .Produces<UserResponse>();

        group.MapPut("/me", UpdateMe)
            .WithName("UpdateMe")
            .WithSummary("Update current user profile")
            .Produces<UserResponse>();

        return group;
    }

    private static async Task<IResult> GetMe(HearHereDbContext db, HttpContext httpContext)
    {
        var user = await httpContext.GetRequiredUserAsync(db);

        var recordingCount = await db.Recordings
            .CountAsync(r => r.UserId == user.Id && r.DeletedAt == null);

        return Results.Ok(new UserResponse
        {
            Id = user.Id.ToString(),
            DisplayName = user.DisplayName,
            RecordingCount = recordingCount,
            CreatedAt = user.CreatedAt
        });
    }

    private static async Task<IResult> UpdateMe(
        UpdateProfileRequest request,
        IValidator<UpdateProfileRequest> validator,
        HearHereDbContext db,
        HttpContext httpContext)
    {
        await validator.ValidateAndThrowAsync(request);

        var user = await httpContext.GetRequiredUserAsync(db);

        if (request.DisplayName is not null)
            user.DisplayName = request.DisplayName;

        if (request.ApnsToken is not null)
            user.ApnsToken = request.ApnsToken;

        user.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync();

        var recordingCount = await db.Recordings
            .CountAsync(r => r.UserId == user.Id && r.DeletedAt == null);

        return Results.Ok(new UserResponse
        {
            Id = user.Id.ToString(),
            DisplayName = user.DisplayName,
            RecordingCount = recordingCount,
            CreatedAt = user.CreatedAt
        });
    }
}
