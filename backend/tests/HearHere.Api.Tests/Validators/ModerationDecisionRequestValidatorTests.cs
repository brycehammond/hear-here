using FluentAssertions;
using HearHere.Api.Validators;
using HearHere.Shared.Models.Requests;
using Xunit;

namespace HearHere.Api.Tests.Validators;

public class ModerationDecisionRequestValidatorTests
{
    private readonly ModerationDecisionRequestValidator _validator = new();

    [Theory]
    [InlineData("approved")]
    [InlineData("rejected")]
    public async Task ValidDecision_Passes(string decision)
    {
        var request = new ModerationDecisionRequest { Decision = decision };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public async Task ValidDecisionWithNotes_Passes()
    {
        var request = new ModerationDecisionRequest
        {
            Decision = "approved",
            Notes = "Content looks fine"
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData("")]
    [InlineData("pending")]
    [InlineData("APPROVED")]
    [InlineData("Rejected")]
    [InlineData("invalid")]
    public async Task InvalidDecision_Fails(string decision)
    {
        var request = new ModerationDecisionRequest { Decision = decision };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Decision");
    }

    [Fact]
    public async Task NotesTooLong_Fails()
    {
        var request = new ModerationDecisionRequest
        {
            Decision = "approved",
            Notes = new string('x', 2001)
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Notes");
    }

    [Fact]
    public async Task NotesAtMaxLength_Passes()
    {
        var request = new ModerationDecisionRequest
        {
            Decision = "approved",
            Notes = new string('x', 2000)
        };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeTrue();
    }
}
