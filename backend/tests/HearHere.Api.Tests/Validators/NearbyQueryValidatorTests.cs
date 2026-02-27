using FluentAssertions;
using HearHere.Api.Validators;
using Xunit;

namespace HearHere.Api.Tests.Validators;

public class NearbyQueryValidatorTests
{
    private readonly NearbyQueryValidator _validator = new();

    [Fact]
    public async Task ValidQuery_Passes()
    {
        var query = new NearbyQuery
        {
            Lat = 40.7128,
            Lng = -74.0060,
            Radius = 500,
            Limit = 20
        };

        var result = await _validator.ValidateAsync(query);

        result.IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData(-91)]
    [InlineData(91)]
    public async Task LatOutOfRange_Fails(double lat)
    {
        var query = new NearbyQuery
        {
            Lat = lat,
            Lng = -74.0060,
            Radius = 500,
            Limit = 20
        };

        var result = await _validator.ValidateAsync(query);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Lat");
    }

    [Theory]
    [InlineData(-90)]
    [InlineData(90)]
    public async Task LatAtBoundary_Passes(double lat)
    {
        var query = new NearbyQuery
        {
            Lat = lat,
            Lng = -74.0060,
            Radius = 500,
            Limit = 20
        };

        var result = await _validator.ValidateAsync(query);

        result.IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData(-181)]
    [InlineData(181)]
    public async Task LngOutOfRange_Fails(double lng)
    {
        var query = new NearbyQuery
        {
            Lat = 40.7128,
            Lng = lng,
            Radius = 500,
            Limit = 20
        };

        var result = await _validator.ValidateAsync(query);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Lng");
    }

    [Theory]
    [InlineData(-180)]
    [InlineData(180)]
    public async Task LngAtBoundary_Passes(double lng)
    {
        var query = new NearbyQuery
        {
            Lat = 40.7128,
            Lng = lng,
            Radius = 500,
            Limit = 20
        };

        var result = await _validator.ValidateAsync(query);

        result.IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData(49)]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(5001)]
    public async Task RadiusOutOfRange_Fails(int radius)
    {
        var query = new NearbyQuery
        {
            Lat = 40.7128,
            Lng = -74.0060,
            Radius = radius,
            Limit = 20
        };

        var result = await _validator.ValidateAsync(query);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Radius");
    }

    [Theory]
    [InlineData(50)]
    [InlineData(5000)]
    public async Task RadiusAtBoundary_Passes(int radius)
    {
        var query = new NearbyQuery
        {
            Lat = 40.7128,
            Lng = -74.0060,
            Radius = radius,
            Limit = 20
        };

        var result = await _validator.ValidateAsync(query);

        result.IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(51)]
    public async Task LimitOutOfRange_Fails(int limit)
    {
        var query = new NearbyQuery
        {
            Lat = 40.7128,
            Lng = -74.0060,
            Radius = 500,
            Limit = limit
        };

        var result = await _validator.ValidateAsync(query);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Limit");
    }

    [Theory]
    [InlineData(1)]
    [InlineData(50)]
    public async Task LimitAtBoundary_Passes(int limit)
    {
        var query = new NearbyQuery
        {
            Lat = 40.7128,
            Lng = -74.0060,
            Radius = 500,
            Limit = limit
        };

        var result = await _validator.ValidateAsync(query);

        result.IsValid.Should().BeTrue();
    }
}
