using System.Security.Claims;
using HearHere.Shared.Data;
using HearHere.Shared.Data.Entities;
using HearHere.Shared.Exceptions;
using Microsoft.EntityFrameworkCore;

namespace HearHere.Api.Auth;

public static class HttpContextAuthExtensions
{
    /// <summary>
    /// Extracts the Entra ID object identifier from the authenticated user's claims.
    /// Tries the standard "oid" claim first, then falls back to NameIdentifier.
    /// </summary>
    public static string GetExternalId(this HttpContext httpContext)
    {
        var oid = httpContext.User.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier")?.Value
                  ?? httpContext.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;

        if (string.IsNullOrEmpty(oid))
            throw new UnauthorizedAccessException("User identity not found in token.");

        return oid;
    }

    /// <summary>
    /// Extracts the identity provider from the authenticated user's claims.
    /// Maps federated provider domains (google.com, apple.com) to short names.
    /// Defaults to "entra" for direct Entra ID sign-ups.
    /// </summary>
    public static string GetIdentityProvider(this HttpContext httpContext)
    {
        var idp = httpContext.User.FindFirst("http://schemas.microsoft.com/identity/claims/identityprovider")?.Value
                  ?? httpContext.User.FindFirst("idp")?.Value;

        return idp switch
        {
            "google.com" => "google",
            "apple.com" => "apple",
            _ => "entra"
        };
    }

    /// <summary>
    /// Resolves the internal database User for the current authenticated request.
    /// Throws NotFoundException if the user has not registered yet.
    /// </summary>
    public static async Task<User> GetRequiredUserAsync(this HttpContext httpContext, HearHereDbContext db)
    {
        var externalId = httpContext.GetExternalId();
        var user = await db.Users.FirstOrDefaultAsync(u => u.ExternalId == externalId);

        if (user is null)
            throw new NotFoundException("User not found. Please register first.");

        return user;
    }
}
