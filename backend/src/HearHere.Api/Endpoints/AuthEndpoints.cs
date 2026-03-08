using FluentValidation;
using HearHere.Api.Auth;
using HearHere.Shared.Data;
using HearHere.Shared.Data.Entities;
using HearHere.Shared.Exceptions;
using HearHere.Shared.Models.Requests;
using HearHere.Shared.Models.Responses;
using Microsoft.EntityFrameworkCore;

namespace HearHere.Api.Endpoints;

public static class AuthEndpoints
{
    public static RouteGroupBuilder MapAuthEndpoints(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/v1/auth")
            .RequireAuthorization()
            .WithTags("Auth");

        group.MapPost("/register", Register)
            .WithName("Register")
            .WithSummary("Register a new user account")
            .Produces<UserResponse>(StatusCodes.Status201Created);

        return group;
    }

    private static async Task<IResult> Register(
        RegisterRequest request,
        IValidator<RegisterRequest> validator,
        HearHereDbContext db,
        HttpContext httpContext)
    {
        await validator.ValidateAndThrowAsync(request);

        var externalId = httpContext.GetExternalId();

        var existingUser = await db.Users.FirstOrDefaultAsync(u => u.ExternalId == externalId);
        if (existingUser is not null)
            throw new ConflictException("User already exists.");

        var user = new User
        {
            ExternalId = externalId,
            DisplayName = request.DisplayName,
            Email = httpContext.User.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value,
            IdentityProvider = httpContext.GetIdentityProvider()
        };

        db.Users.Add(user);
        await db.SaveChangesAsync();

        return Results.Created($"/v1/users/me", new UserResponse
        {
            Id = user.Id.ToString(),
            DisplayName = user.DisplayName,
            IdentityProvider = user.IdentityProvider,
            RecordingCount = 0,
            CreatedAt = user.CreatedAt
        });
    }
}
