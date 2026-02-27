using FluentAssertions;
using HearHere.Api.Validators;
using HearHere.Shared.Models.Requests;
using Xunit;

namespace HearHere.Api.Tests.Validators;

public class RegisterRequestValidatorTests
{
    private readonly RegisterRequestValidator _validator = new();

    [Fact]
    public async Task ValidRequest_Passes()
    {
        var request = new RegisterRequest { DisplayName = "Alice" };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public async Task EmptyDisplayName_Fails()
    {
        var request = new RegisterRequest { DisplayName = "" };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "DisplayName");
    }

    [Fact]
    public async Task TooLongDisplayName_Fails()
    {
        var request = new RegisterRequest { DisplayName = new string('a', 51) };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "DisplayName");
    }

    [Fact]
    public async Task DisplayNameAtMaxLength_Passes()
    {
        var request = new RegisterRequest { DisplayName = new string('a', 50) };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public async Task ControlCharactersInDisplayName_Fails()
    {
        var request = new RegisterRequest { DisplayName = "Alice\u0000Bob" };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "DisplayName");
    }

    [Fact]
    public async Task TabCharacterInDisplayName_Fails()
    {
        var request = new RegisterRequest { DisplayName = "Alice\tBob" };

        var result = await _validator.ValidateAsync(request);

        result.IsValid.Should().BeFalse();
    }
}
