using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using FluentAssertions;
using Xunit;

namespace HearHere.Api.Tests.Endpoints;

public class AdminEndpointTests
{
    private readonly HearHereWebApplicationFactory _factory = new();

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
    };

    private void SetupAdminClaims(string externalId)
    {
        TestAuthHandler.AdditionalClaims[externalId] =
        [
            new Claim("extension_Role", "admin")
        ];
    }

    [Fact]
    public async Task GetQueue_NonAdmin_Returns403()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var externalId = $"admin-nonadmin-{Guid.NewGuid():N}";
        TestDataHelper.CreateUser(db, externalId, "Regular User");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        var response = await client.GetAsync("/v1/admin/moderation/queue");

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task GetQueue_Admin_ReturnsPendingReviewRecordings()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var adminExternalId = $"admin-queue-{Guid.NewGuid():N}";
        SetupAdminClaims(adminExternalId);
        TestDataHelper.CreateUser(db, adminExternalId, "Admin User", "admin");

        var ownerExternalId = $"admin-queue-own-{Guid.NewGuid():N}";
        var owner = TestDataHelper.CreateUser(db, ownerExternalId, "Owner");
        TestDataHelper.CreateRecording(db, owner.Id, "pending_review", "Needs Review");
        TestDataHelper.CreateRecording(db, owner.Id, "approved", "Already Approved");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", adminExternalId);

        var response = await client.GetAsync("/v1/admin/moderation/queue");

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var items = doc.RootElement.GetProperty("items");
        items.GetArrayLength().Should().Be(1);
        items[0].GetProperty("subject").GetString().Should().Be("Needs Review");
    }

    [Fact]
    public async Task PostDecision_ApprovesRecording()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var adminExternalId = $"admin-approve-{Guid.NewGuid():N}";
        SetupAdminClaims(adminExternalId);
        TestDataHelper.CreateUser(db, adminExternalId, "Admin User", "admin");

        var ownerExternalId = $"admin-approve-own-{Guid.NewGuid():N}";
        var owner = TestDataHelper.CreateUser(db, ownerExternalId, "Owner");
        var recording = TestDataHelper.CreateRecording(db, owner.Id, "pending_review", "Review Me");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", adminExternalId);

        var request = new { decision = "approved", notes = "Looks good" };
        var response = await client.PostAsJsonAsync(
            $"/v1/admin/moderation/{recording.Id}/decision", request, JsonOptions);

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        doc.RootElement.GetProperty("status").GetString().Should().Be("approved");
    }

    [Fact]
    public async Task PostDecision_RejectsRecording()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var adminExternalId = $"admin-reject-{Guid.NewGuid():N}";
        SetupAdminClaims(adminExternalId);
        TestDataHelper.CreateUser(db, adminExternalId, "Admin User", "admin");

        var ownerExternalId = $"admin-reject-own-{Guid.NewGuid():N}";
        var owner = TestDataHelper.CreateUser(db, ownerExternalId, "Owner");
        var recording = TestDataHelper.CreateRecording(db, owner.Id, "pending_review", "Bad Content");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", adminExternalId);

        var request = new { decision = "rejected", notes = "Inappropriate content" };
        var response = await client.PostAsJsonAsync(
            $"/v1/admin/moderation/{recording.Id}/decision", request, JsonOptions);

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        doc.RootElement.GetProperty("status").GetString().Should().Be("rejected");
    }

    [Fact]
    public async Task PostDecision_FailsIfNotPendingReview()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var adminExternalId = $"admin-conflict-{Guid.NewGuid():N}";
        SetupAdminClaims(adminExternalId);
        TestDataHelper.CreateUser(db, adminExternalId, "Admin User", "admin");

        var ownerExternalId = $"admin-conflict-own-{Guid.NewGuid():N}";
        var owner = TestDataHelper.CreateUser(db, ownerExternalId, "Owner");
        var recording = TestDataHelper.CreateRecording(db, owner.Id, "approved", "Already Done");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", adminExternalId);

        var request = new { decision = "approved", notes = "Try again" };
        var response = await client.PostAsJsonAsync(
            $"/v1/admin/moderation/{recording.Id}/decision", request, JsonOptions);

        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task GetStats_NonAdmin_Returns403()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var externalId = $"admin-stats-nonadmin-{Guid.NewGuid():N}";
        TestDataHelper.CreateUser(db, externalId, "Regular User");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        var response = await client.GetAsync("/v1/admin/moderation/stats");

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }
}
