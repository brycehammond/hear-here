using System.Net;
using System.Net.Http.Json;
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
}
