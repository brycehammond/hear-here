using FluentValidation;
using HearHere.Shared.Models.Requests;

namespace HearHere.Api.Validators;

public class RegisterRequestValidator : AbstractValidator<RegisterRequest>
{
    public RegisterRequestValidator()
    {
        RuleFor(x => x.DisplayName)
            .NotEmpty().WithMessage("Display name is required.")
            .Length(1, 50).WithMessage("Display name must be between 1 and 50 characters.")
            .Must(name => name is null || !name.Any(char.IsControl)).WithMessage("Display name must not contain control characters.");
    }
}
