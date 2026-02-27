using System.Net;
using FluentAssertions;
using Xunit;

namespace HearHere.Api.Tests.Endpoints;

public class HealthEndpointTests
{
    private readonly HearHereWebApplicationFactory _factory = new();

    [Fact]
    public async Task Health_ReturnsOk()
    {
        var client = _factory.CreateClient();

        var response = await client.GetAsync("/health");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
    }
}
