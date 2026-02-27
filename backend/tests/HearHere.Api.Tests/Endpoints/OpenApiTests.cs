using System.Text.Json;
using FluentAssertions;
using Xunit;

namespace HearHere.Api.Tests.Endpoints;

public class OpenApiTests
{
    private readonly HearHereWebApplicationFactory _factory = new();
    private HttpClient Client => _factory.CreateClient();

    private async Task<JsonDocument> GetOpenApiDocumentAsync()
    {
        var response = await Client.GetAsync("/openapi/v1.json");
        response.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);

        var content = await response.Content.ReadAsStringAsync();
        return JsonDocument.Parse(content);
    }

    [Fact]
    public async Task OpenApiDocument_IsServedAtCorrectUrl()
    {
        var response = await Client.GetAsync("/openapi/v1.json");

        response.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);
        response.Content.Headers.ContentType?.MediaType.Should().Be("application/json");
    }

    [Fact]
    public async Task OpenApiDocument_HasApiInfo()
    {
        var doc = await GetOpenApiDocumentAsync();
        var info = doc.RootElement.GetProperty("info");

        info.GetProperty("title").GetString().Should().Be("HearHere API");
        info.GetProperty("version").GetString().Should().Be("v1");
    }

    [Fact]
    public async Task OpenApiDocument_HasBearerSecurityScheme()
    {
        var doc = await GetOpenApiDocumentAsync();
        var components = doc.RootElement.GetProperty("components");
        var securitySchemes = components.GetProperty("securitySchemes");
        var bearer = securitySchemes.GetProperty("Bearer");

        bearer.GetProperty("type").GetString().Should().Be("http");
        bearer.GetProperty("scheme").GetString().Should().Be("bearer");
        bearer.GetProperty("bearerFormat").GetString().Should().Be("JWT");
    }

    [Theory]
    [InlineData("/v1/auth/register")]
    [InlineData("/v1/users/me")]
    [InlineData("/v1/recordings")]
    [InlineData("/v1/recordings/mine")]
    [InlineData("/v1/recordings/{id}")]
    [InlineData("/v1/recordings/{id}/upload-complete")]
    [InlineData("/v1/recordings/{id}/playback")]
    [InlineData("/v1/recordings/nearby")]
    [InlineData("/v1/reports")]
    [InlineData("/v1/admin/moderation/queue")]
    [InlineData("/v1/admin/moderation/{recordingId}/decision")]
    [InlineData("/v1/admin/moderation/stats")]
    public async Task OpenApiDocument_ContainsEndpoint(string expectedPath)
    {
        var doc = await GetOpenApiDocumentAsync();
        var paths = doc.RootElement.GetProperty("paths");

        paths.TryGetProperty(expectedPath, out _).Should().BeTrue(
            $"expected path '{expectedPath}' to exist in OpenAPI document");
    }

    [Fact]
    public async Task OpenApiDocument_DoesNotContainHealthEndpoint()
    {
        var doc = await GetOpenApiDocumentAsync();
        var paths = doc.RootElement.GetProperty("paths");

        paths.TryGetProperty("/health", out _).Should().BeFalse(
            "health endpoint should be excluded from OpenAPI document");
    }

    [Theory]
    [InlineData("/v1/auth/register", "Auth")]
    [InlineData("/v1/users/me", "Users")]
    [InlineData("/v1/recordings", "Recordings")]
    [InlineData("/v1/recordings/mine", "Recordings")]
    [InlineData("/v1/recordings/{id}", "Recordings")]
    [InlineData("/v1/recordings/{id}/upload-complete", "Recordings")]
    [InlineData("/v1/recordings/{id}/playback", "Recordings")]
    [InlineData("/v1/recordings/nearby", "Discovery")]
    [InlineData("/v1/reports", "Reports")]
    [InlineData("/v1/admin/moderation/queue", "Admin")]
    [InlineData("/v1/admin/moderation/{recordingId}/decision", "Admin")]
    [InlineData("/v1/admin/moderation/stats", "Admin")]
    public async Task OpenApiDocument_EndpointsHaveCorrectTags(string path, string expectedTag)
    {
        var doc = await GetOpenApiDocumentAsync();
        var pathItem = doc.RootElement.GetProperty("paths").GetProperty(path);

        // Get the first operation (get, post, put, delete, etc.)
        var operation = pathItem.EnumerateObject().First().Value;
        var tags = operation.GetProperty("tags");

        tags.EnumerateArray().Select(t => t.GetString()).Should().Contain(expectedTag);
    }

    [Fact]
    public async Task OpenApiDocument_RegisterEndpoint_Returns201()
    {
        var doc = await GetOpenApiDocumentAsync();
        var post = doc.RootElement
            .GetProperty("paths")
            .GetProperty("/v1/auth/register")
            .GetProperty("post")
            .GetProperty("responses");

        post.TryGetProperty("201", out _).Should().BeTrue();
    }

    [Fact]
    public async Task OpenApiDocument_CreateRecordingEndpoint_Returns201()
    {
        var doc = await GetOpenApiDocumentAsync();
        var post = doc.RootElement
            .GetProperty("paths")
            .GetProperty("/v1/recordings")
            .GetProperty("post")
            .GetProperty("responses");

        post.TryGetProperty("201", out _).Should().BeTrue();
    }

    [Fact]
    public async Task OpenApiDocument_DeleteRecordingEndpoint_Returns204()
    {
        var doc = await GetOpenApiDocumentAsync();
        var delete = doc.RootElement
            .GetProperty("paths")
            .GetProperty("/v1/recordings/{id}")
            .GetProperty("delete")
            .GetProperty("responses");

        delete.TryGetProperty("204", out _).Should().BeTrue();
    }

    [Fact]
    public async Task OpenApiDocument_CreateReportEndpoint_Returns201()
    {
        var doc = await GetOpenApiDocumentAsync();
        var post = doc.RootElement
            .GetProperty("paths")
            .GetProperty("/v1/reports")
            .GetProperty("post")
            .GetProperty("responses");

        post.TryGetProperty("201", out _).Should().BeTrue();
    }
}
