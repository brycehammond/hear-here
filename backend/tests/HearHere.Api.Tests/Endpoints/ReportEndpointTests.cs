using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using FluentAssertions;
using Xunit;

namespace HearHere.Api.Tests.Endpoints;

public class ReportEndpointTests
{
    private readonly HearHereWebApplicationFactory _factory = new();

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
    };

    [Fact]
    public async Task CreateReport_ReturnsCreated()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var ownerExternalId = $"report-owner-{Guid.NewGuid():N}";
        var reporterExternalId = $"report-reporter-{Guid.NewGuid():N}";
        var owner = TestDataHelper.CreateUser(db, ownerExternalId, "Owner");
        TestDataHelper.CreateUser(db, reporterExternalId, "Reporter");
        var recording = TestDataHelper.CreateRecording(db, owner.Id, "approved");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", reporterExternalId);

        var request = new { recording_id = recording.Id, reason = "spam" };
        var response = await client.PostAsJsonAsync("/v1/reports", request, JsonOptions);

        response.StatusCode.Should().Be(HttpStatusCode.Created);

        var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        doc.RootElement.GetProperty("recording_id").GetGuid().Should().Be(recording.Id);
        doc.RootElement.GetProperty("status").GetString().Should().Be("submitted");
    }

    [Fact]
    public async Task CreateReport_CannotReportOwnRecording_Returns403()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var externalId = $"report-self-{Guid.NewGuid():N}";
        var user = TestDataHelper.CreateUser(db, externalId, "Self Reporter");
        var recording = TestDataHelper.CreateRecording(db, user.Id, "approved");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        var request = new { recording_id = recording.Id, reason = "spam" };
        var response = await client.PostAsJsonAsync("/v1/reports", request, JsonOptions);

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task CreateReport_DuplicateReport_Returns409()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var ownerExternalId = $"report-dup-own-{Guid.NewGuid():N}";
        var reporterExternalId = $"report-dup-rep-{Guid.NewGuid():N}";
        var owner = TestDataHelper.CreateUser(db, ownerExternalId, "Owner");
        TestDataHelper.CreateUser(db, reporterExternalId, "Reporter");
        var recording = TestDataHelper.CreateRecording(db, owner.Id, "approved");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", reporterExternalId);

        var request = new { recording_id = recording.Id, reason = "spam" };
        await client.PostAsJsonAsync("/v1/reports", request, JsonOptions);

        var response = await client.PostAsJsonAsync("/v1/reports", request, JsonOptions);

        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task CreateReport_ThreeDistinctReporters_EscalatesToPendingReview()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var ownerExternalId = $"report-esc-own-{Guid.NewGuid():N}";
        var owner = TestDataHelper.CreateUser(db, ownerExternalId, "Owner");
        var recording = TestDataHelper.CreateRecording(db, owner.Id, "approved");

        for (int i = 0; i < 3; i++)
        {
            var reporterExternalId = $"report-esc-{i}-{Guid.NewGuid():N}";
            TestDataHelper.CreateUser(db, reporterExternalId, $"Reporter {i}");

            var client = _factory.CreateClient();
            client.DefaultRequestHeaders.Add("X-Test-External-Id", reporterExternalId);

            var request = new { recording_id = recording.Id, reason = "spam" };
            await client.PostAsJsonAsync("/v1/reports", request, JsonOptions);
        }

        // Verify recording status changed to pending_review
        var freshDb = TestDataHelper.GetDbContext(_factory.Services);
        var updatedRecording = await freshDb.Recordings.FindAsync(recording.Id);
        updatedRecording!.Status.Should().Be("pending_review");
    }
}
