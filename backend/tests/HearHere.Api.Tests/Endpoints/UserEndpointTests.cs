using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using FluentAssertions;
using Xunit;

namespace HearHere.Api.Tests.Endpoints;

public class UserEndpointTests
{
    private readonly HearHereWebApplicationFactory _factory = new();

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
    };

    [Fact]
    public async Task GetMe_ReturnsUserProfile_WithRecordingCount()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var externalId = $"user-me-{Guid.NewGuid():N}";
        var user = TestDataHelper.CreateUser(db, externalId, "Profile User");
        TestDataHelper.CreateRecording(db, user.Id, "approved");
        TestDataHelper.CreateRecording(db, user.Id, "pending_moderation");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        var response = await client.GetAsync("/v1/users/me");

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        doc.RootElement.GetProperty("display_name").GetString().Should().Be("Profile User");
        doc.RootElement.GetProperty("recording_count").GetInt32().Should().Be(2);
    }

    [Fact]
    public async Task UpdateMe_UpdatesDisplayName()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var externalId = $"user-upd-{Guid.NewGuid():N}";
        TestDataHelper.CreateUser(db, externalId, "Old Name");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        var request = new { display_name = "New Name" };
        var response = await client.PutAsJsonAsync("/v1/users/me", request, JsonOptions);

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        doc.RootElement.GetProperty("display_name").GetString().Should().Be("New Name");
    }

    [Fact]
    public async Task GetMe_UnregisteredUser_Returns404()
    {
        var client = _factory.CreateClient();
        var externalId = $"user-unreg-{Guid.NewGuid():N}";
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        var response = await client.GetAsync("/v1/users/me");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }
}
