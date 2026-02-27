using System.Net;
using FluentAssertions;
using Xunit;

namespace HearHere.Api.Tests.Endpoints;

public class DiscoveryEndpointTests
{
    private readonly HearHereWebApplicationFactory _factory = new();

    [Fact]
    public async Task Nearby_InvalidLatitude_Returns400()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var externalId = $"disc-val-{Guid.NewGuid():N}";
        TestDataHelper.CreateUser(db, externalId, "Discovery User");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        // lat out of range (-91 is below -90 minimum)
        var response = await client.GetAsync("/v1/recordings/nearby?lat=-91&lng=-74.006");

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Nearby_RadiusOutOfRange_Returns400()
    {
        var db = TestDataHelper.GetDbContext(_factory.Services);
        var externalId = $"disc-radius-{Guid.NewGuid():N}";
        TestDataHelper.CreateUser(db, externalId, "Discovery User");

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-External-Id", externalId);

        // Radius 10 is below minimum of 50
        var response = await client.GetAsync("/v1/recordings/nearby?lat=40.7128&lng=-74.006&radius=10");

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }
}
