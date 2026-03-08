using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using FluentAssertions;
using Xunit;

namespace HearHere.Api.Tests.Endpoints;

public class AuthEndpointTests
{
    private readonly HearHereWebApplicationFactory _factory = new();

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
    };

    [Fact]
    public async Task Register_HappyPath_CreatesUser_Returns201()
    {
        var client = _factory.CreateClient();
        var externalId = $"auth-test-{Guid.NewGuid():N}";
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        var request = new { display_name = "Test User" };
        var response = await client.PostAsJsonAsync("/v1/auth/register", request, JsonOptions);

        response.StatusCode.Should().Be(HttpStatusCode.Created);

        var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        doc.RootElement.GetProperty("display_name").GetString().Should().Be("Test User");
        doc.RootElement.GetProperty("id").GetString().Should().NotBeNullOrEmpty();
        doc.RootElement.GetProperty("recording_count").GetInt32().Should().Be(0);
    }

    [Fact]
    public async Task Register_WithGoogleIdp_StoresIdentityProvider()
    {
        var client = _factory.CreateClient();
        var externalId = $"auth-google-{Guid.NewGuid():N}";
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        TestAuthHandler.AdditionalClaims[externalId] =
        [
            new Claim("http://schemas.microsoft.com/identity/claims/identityprovider", "google.com")
        ];

        var request = new { display_name = "Google User" };
        var response = await client.PostAsJsonAsync("/v1/auth/register", request, JsonOptions);

        response.StatusCode.Should().Be(HttpStatusCode.Created);

        var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        doc.RootElement.GetProperty("identity_provider").GetString().Should().Be("google");
    }

    [Fact]
    public async Task Register_WithAppleIdp_StoresIdentityProvider()
    {
        var client = _factory.CreateClient();
        var externalId = $"auth-apple-{Guid.NewGuid():N}";
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        TestAuthHandler.AdditionalClaims[externalId] =
        [
            new Claim("http://schemas.microsoft.com/identity/claims/identityprovider", "apple.com")
        ];

        var request = new { display_name = "Apple User" };
        var response = await client.PostAsJsonAsync("/v1/auth/register", request, JsonOptions);

        response.StatusCode.Should().Be(HttpStatusCode.Created);

        var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        doc.RootElement.GetProperty("identity_provider").GetString().Should().Be("apple");
    }

    [Fact]
    public async Task Register_WithNoIdpClaim_DefaultsToEntra()
    {
        var client = _factory.CreateClient();
        var externalId = $"auth-entra-{Guid.NewGuid():N}";
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        var request = new { display_name = "Entra User" };
        var response = await client.PostAsJsonAsync("/v1/auth/register", request, JsonOptions);

        response.StatusCode.Should().Be(HttpStatusCode.Created);

        var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        doc.RootElement.GetProperty("identity_provider").GetString().Should().Be("entra");
    }

    [Fact]
    public async Task Register_Duplicate_Returns409()
    {
        var client = _factory.CreateClient();
        var externalId = $"auth-dup-{Guid.NewGuid():N}";
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        var request = new { display_name = "Test User" };
        await client.PostAsJsonAsync("/v1/auth/register", request, JsonOptions);

        var response = await client.PostAsJsonAsync("/v1/auth/register", request, JsonOptions);

        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task Register_EmptyDisplayName_Returns400()
    {
        var client = _factory.CreateClient();
        var externalId = $"auth-val-{Guid.NewGuid():N}";
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        var request = new { display_name = "" };
        var response = await client.PostAsJsonAsync("/v1/auth/register", request, JsonOptions);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task GetMe_ReturnsIdentityProvider()
    {
        var client = _factory.CreateClient();
        var externalId = $"auth-me-{Guid.NewGuid():N}";
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        TestAuthHandler.AdditionalClaims[externalId] =
        [
            new Claim("http://schemas.microsoft.com/identity/claims/identityprovider", "google.com")
        ];

        // Register first
        var registerRequest = new { display_name = "Me User" };
        await client.PostAsJsonAsync("/v1/auth/register", registerRequest, JsonOptions);

        // Get profile
        var response = await client.GetAsync("/v1/users/me");

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        doc.RootElement.GetProperty("identity_provider").GetString().Should().Be("google");
    }
}
