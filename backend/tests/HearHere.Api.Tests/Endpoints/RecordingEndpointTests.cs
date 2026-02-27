using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using FluentAssertions;
using Xunit;

namespace HearHere.Api.Tests.Endpoints;

public class RecordingEndpointTests
{
    private readonly HearHereWebApplicationFactory _factory = new();

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
    };

    [Fact]
    public async Task Create_ReturnsCreated_WithUploadUrl()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var externalId = $"rec-create-{Guid.NewGuid():N}";
        TestDataHelper.CreateUser(db, externalId, "Creator");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        var request = new
        {
            subject = "My Recording",
            latitude = 40.7128,
            longitude = -74.006,
            duration_sec = 60
        };
        var response = await client.PostAsJsonAsync("/v1/recordings", request, JsonOptions);

        response.StatusCode.Should().Be(HttpStatusCode.Created);

        var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        doc.RootElement.GetProperty("status").GetString().Should().Be("pending_upload");
        doc.RootElement.GetProperty("upload_url").GetString().Should().NotBeNullOrEmpty();
        doc.RootElement.GetProperty("id").GetGuid().Should().NotBeEmpty();
    }

    [Fact]
    public async Task GetById_OwnerSeesPendingRecording()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var externalId = $"rec-owner-{Guid.NewGuid():N}";
        var user = TestDataHelper.CreateUser(db, externalId, "Owner");
        var recording = TestDataHelper.CreateRecording(db, user.Id, "pending_upload", "Pending Rec");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        var response = await client.GetAsync($"/v1/recordings/{recording.Id}");

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        doc.RootElement.GetProperty("subject").GetString().Should().Be("Pending Rec");
        doc.RootElement.GetProperty("status").GetString().Should().Be("pending_upload");
    }

    [Fact]
    public async Task GetById_NonOwnerCannotSeePendingRecording()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var ownerExternalId = $"rec-owner2-{Guid.NewGuid():N}";
        var otherExternalId = $"rec-other-{Guid.NewGuid():N}";
        var owner = TestDataHelper.CreateUser(db, ownerExternalId, "Owner");
        TestDataHelper.CreateUser(db, otherExternalId, "Other");
        var recording = TestDataHelper.CreateRecording(db, owner.Id, "pending_upload");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", otherExternalId);

        var response = await client.GetAsync($"/v1/recordings/{recording.Id}");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task GetById_AnyoneCanSeeApprovedRecording()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var ownerExternalId = $"rec-owner3-{Guid.NewGuid():N}";
        var viewerExternalId = $"rec-viewer-{Guid.NewGuid():N}";
        var owner = TestDataHelper.CreateUser(db, ownerExternalId, "Owner");
        TestDataHelper.CreateUser(db, viewerExternalId, "Viewer");
        var recording = TestDataHelper.CreateRecording(db, owner.Id, "approved", "Public Rec");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", viewerExternalId);

        var response = await client.GetAsync($"/v1/recordings/{recording.Id}");

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        doc.RootElement.GetProperty("subject").GetString().Should().Be("Public Rec");
    }

    [Fact]
    public async Task Delete_SoftDeletesOwnRecording()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var externalId = $"rec-del-{Guid.NewGuid():N}";
        var user = TestDataHelper.CreateUser(db, externalId, "Deleter");
        var recording = TestDataHelper.CreateRecording(db, user.Id, "approved");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        var response = await client.DeleteAsync($"/v1/recordings/{recording.Id}");

        response.StatusCode.Should().Be(HttpStatusCode.NoContent);

        // Verify soft delete by trying to GET it
        var getResponse = await client.GetAsync($"/v1/recordings/{recording.Id}");
        getResponse.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Delete_CannotDeleteAnotherUsersRecording()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var ownerExternalId = $"rec-delown-{Guid.NewGuid():N}";
        var otherExternalId = $"rec-deloth-{Guid.NewGuid():N}";
        var owner = TestDataHelper.CreateUser(db, ownerExternalId, "Owner");
        TestDataHelper.CreateUser(db, otherExternalId, "Other");
        var recording = TestDataHelper.CreateRecording(db, owner.Id, "approved");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", otherExternalId);

        var response = await client.DeleteAsync($"/v1/recordings/{recording.Id}");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Mine_ReturnsUserRecordings_WithPagination()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var externalId = $"rec-mine-{Guid.NewGuid():N}";
        var user = TestDataHelper.CreateUser(db, externalId, "Mine User");
        TestDataHelper.CreateRecording(db, user.Id, "approved", "Rec 1");
        TestDataHelper.CreateRecording(db, user.Id, "pending_moderation", "Rec 2");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        var response = await client.GetAsync("/v1/recordings/mine");

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        doc.RootElement.GetProperty("items").GetArrayLength().Should().Be(2);
    }

    [Fact]
    public async Task Mine_FiltersByStatus()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var externalId = $"rec-filter-{Guid.NewGuid():N}";
        var user = TestDataHelper.CreateUser(db, externalId, "Filter User");
        TestDataHelper.CreateRecording(db, user.Id, "approved", "Approved Rec");
        TestDataHelper.CreateRecording(db, user.Id, "pending_moderation", "Pending Rec");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        var response = await client.GetAsync("/v1/recordings/mine?status=approved");

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var items = doc.RootElement.GetProperty("items");
        items.GetArrayLength().Should().Be(1);
        items[0].GetProperty("status").GetString().Should().Be("approved");
    }

    [Fact]
    public async Task UploadComplete_TransitionsToPendingModeration()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var externalId = $"rec-upload-{Guid.NewGuid():N}";
        var user = TestDataHelper.CreateUser(db, externalId, "Uploader");
        var recording = TestDataHelper.CreateRecording(db, user.Id, "pending_upload", "Upload Rec");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        var response = await client.PostAsync($"/v1/recordings/{recording.Id}/upload-complete", null);

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        doc.RootElement.GetProperty("status").GetString().Should().Be("pending_moderation");
    }

    [Fact]
    public async Task UploadComplete_FailsIfNotPendingUpload()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var externalId = $"rec-upconf-{Guid.NewGuid():N}";
        var user = TestDataHelper.CreateUser(db, externalId, "Uploader");
        var recording = TestDataHelper.CreateRecording(db, user.Id, "approved", "Already Approved");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        var response = await client.PostAsync($"/v1/recordings/{recording.Id}/upload-complete", null);

        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task Playback_ReturnsPlaybackUrl_ForApprovedRecording()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var ownerExternalId = $"rec-play-own-{Guid.NewGuid():N}";
        var viewerExternalId = $"rec-play-view-{Guid.NewGuid():N}";
        var owner = TestDataHelper.CreateUser(db, ownerExternalId, "Owner");
        TestDataHelper.CreateUser(db, viewerExternalId, "Viewer");
        var recording = TestDataHelper.CreateRecording(db, owner.Id, "approved", "Playable Rec");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", viewerExternalId);

        var response = await client.GetAsync($"/v1/recordings/{recording.Id}/playback");

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        doc.RootElement.GetProperty("playback_url").GetString().Should().NotBeNullOrEmpty();
        doc.RootElement.GetProperty("duration_sec").GetInt32().Should().Be(30);
    }

    [Fact]
    public async Task Playback_OwnerCanPlayOwnNonApprovedRecording()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var externalId = $"rec-play-pend-{Guid.NewGuid():N}";
        var user = TestDataHelper.CreateUser(db, externalId, "Owner");
        var recording = TestDataHelper.CreateRecording(db, user.Id, "pending_moderation", "My Pending Rec");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        var response = await client.GetAsync($"/v1/recordings/{recording.Id}/playback");

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        doc.RootElement.GetProperty("playback_url").GetString().Should().NotBeNullOrEmpty();
    }
}
