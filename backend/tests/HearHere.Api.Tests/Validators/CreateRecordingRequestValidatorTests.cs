using FluentAssertions;
using HearHere.Api.Validators;
using HearHere.Shared.Models.Requests;
using Xunit;

namespace HearHere.Api.Tests.Validators;

public class CreateRecordingRequestValidatorTests
{
    private readonly CreateRecordingRequestValidator _validator = new();

    [Fact]
    public async Task ValidRequest_Passes()
    {
        var request = new CreateRecordingRequest
        {
            Subject = "Test recording",
            Latitude = 40.7128,
            Longitude = -74.0060,
            DurationSec = 60
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public async Task ValidRequestWithDescription_Passes()
    {
        var request = new CreateRecordingRequest
        {
            Subject = "Test recording",
            Description = "A nice recording",
            Latitude = 40.7128,
            Longitude = -74.0060,
            DurationSec = 60
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData("")]
    [InlineData(null)]
    public async Task MissingSubject_Fails(string? subject)
    {
        var request = new CreateRecordingRequest
        {
            Subject = subject!,
            Latitude = 40.7128,
            Longitude = -74.0060,
            DurationSec = 60
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Subject");
    }

    [Fact]
    public async Task SubjectTooLong_Fails()
    {
        var request = new CreateRecordingRequest
        {
            Subject = new string('x', 201),
            Latitude = 40.7128,
            Longitude = -74.0060,
            DurationSec = 60
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Subject");
    }

    [Theory]
    [InlineData(-91)]
    [InlineData(91)]
    public async Task LatitudeOutOfRange_Fails(double latitude)
    {
        var request = new CreateRecordingRequest
        {
            Subject = "Test",
            Latitude = latitude,
            Longitude = -74.0060,
            DurationSec = 60
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Latitude");
    }

    [Theory]
    [InlineData(-90)]
    [InlineData(90)]
    public async Task LatitudeAtBoundary_Passes(double latitude)
    {
        var request = new CreateRecordingRequest
        {
            Subject = "Test",
            Latitude = latitude,
            Longitude = -74.0060,
            DurationSec = 60
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData(-181)]
    [InlineData(181)]
    public async Task LongitudeOutOfRange_Fails(double longitude)
    {
        var request = new CreateRecordingRequest
        {
            Subject = "Test",
            Latitude = 40.7128,
            Longitude = longitude,
            DurationSec = 60
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Longitude");
    }

    [Theory]
    [InlineData(-180)]
    [InlineData(180)]
    public async Task LongitudeAtBoundary_Passes(double longitude)
    {
        var request = new CreateRecordingRequest
        {
            Subject = "Test",
            Latitude = 40.7128,
            Longitude = longitude,
            DurationSec = 60
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(301)]
    public async Task DurationSecOutOfRange_Fails(int durationSec)
    {
        var request = new CreateRecordingRequest
        {
            Subject = "Test",
            Latitude = 40.7128,
            Longitude = -74.0060,
            DurationSec = durationSec
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "DurationSec");
    }

    [Theory]
    [InlineData(1)]
    [InlineData(300)]
    public async Task DurationSecAtBoundary_Passes(int durationSec)
    {
        var request = new CreateRecordingRequest
        {
            Subject = "Test",
            Latitude = 40.7128,
            Longitude = -74.0060,
            DurationSec = durationSec
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public async Task DescriptionTooLong_Fails()
    {
        var request = new CreateRecordingRequest
        {
            Subject = "Test",
            Description = new string('x', 2001),
            Latitude = 40.7128,
            Longitude = -74.0060,
            DurationSec = 60
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Description");
    }

    [Fact]
    public async Task DescriptionAtMaxLength_Passes()
    {
        var request = new CreateRecordingRequest
        {
            Subject = "Test",
            Description = new string('x', 2000),
            Latitude = 40.7128,
            Longitude = -74.0060,
            DurationSec = 60
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeTrue();
    }
}
