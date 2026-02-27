using FluentAssertions;
using HearHere.Api.Validators;
using HearHere.Shared.Models.Requests;
using Xunit;

namespace HearHere.Api.Tests.Validators;

public class CreateReportRequestValidatorTests
{
    private readonly CreateReportRequestValidator _validator = new();

    [Fact]
    public async Task ValidRequest_Passes()
    {
        var request = new CreateReportRequest
        {
            RecordingId = Guid.NewGuid(),
            Reason = "spam"
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public async Task ValidRequestWithDescription_Passes()
    {
        var request = new CreateReportRequest
        {
            RecordingId = Guid.NewGuid(),
            Reason = "spam",
            Description = "This is spam content"
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData("hate_speech")]
    [InlineData("harassment")]
    [InlineData("violence")]
    [InlineData("sexual_content")]
    [InlineData("spam")]
    [InlineData("misinformation")]
    [InlineData("other")]
    public async Task AllValidReasons_Pass(string reason)
    {
        var request = new CreateReportRequest
        {
            RecordingId = Guid.NewGuid(),
            Reason = reason
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData("invalid_reason")]
    [InlineData("SPAM")]
    [InlineData("Hate_Speech")]
    public async Task InvalidReason_Fails(string reason)
    {
        var request = new CreateReportRequest
        {
            RecordingId = Guid.NewGuid(),
            Reason = reason
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Reason");
    }

    [Fact]
    public async Task EmptyReason_Fails()
    {
        var request = new CreateReportRequest
        {
            RecordingId = Guid.NewGuid(),
            Reason = ""
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Reason");
    }

    [Fact]
    public async Task EmptyRecordingId_Fails()
    {
        var request = new CreateReportRequest
        {
            RecordingId = Guid.Empty,
            Reason = "spam"
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "RecordingId");
    }

    [Fact]
    public async Task DescriptionTooLong_Fails()
    {
        var request = new CreateReportRequest
        {
            RecordingId = Guid.NewGuid(),
            Reason = "spam",
            Description = new string('x', 1001)
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Description");
    }

    [Fact]
    public async Task DescriptionAtMaxLength_Passes()
    {
        var request = new CreateReportRequest
        {
            RecordingId = Guid.NewGuid(),
            Reason = "spam",
            Description = new string('x', 1000)
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeTrue();
    }
}
