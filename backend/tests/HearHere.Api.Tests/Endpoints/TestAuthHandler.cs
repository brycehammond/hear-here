using System.Collections.Concurrent;
using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace HearHere.Api.Tests.Endpoints;

public class TestAuthHandler : AuthenticationHandler<AuthenticationSchemeOptions>
{
    public const string SchemeName = "TestScheme";
    public const string DefaultExternalId = "test-default-user";

    public static ConcurrentDictionary<string, List<Claim>> AdditionalClaims { get; } = new();

    public TestAuthHandler(
        IOptionsMonitor<AuthenticationSchemeOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder)
        : base(options, logger, encoder)
    {
    }

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var externalId = Context.Request.Headers["X-Test-External-Id"].FirstOrDefault()
                         ?? DefaultExternalId;

        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, externalId),
            new("http://schemas.microsoft.com/identity/claims/objectidentifier", externalId),
        };

        if (AdditionalClaims.TryGetValue(externalId, out var extra))
        {
            claims.AddRange(extra);
        }

        var identity = new ClaimsIdentity(claims, SchemeName);
        var principal = new ClaimsPrincipal(identity);
        var ticket = new AuthenticationTicket(principal, SchemeName);

        return Task.FromResult(AuthenticateResult.Success(ticket));
    }
}
