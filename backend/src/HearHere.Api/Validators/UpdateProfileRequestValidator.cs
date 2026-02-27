using FluentValidation;
using HearHere.Shared.Models.Requests;

namespace HearHere.Api.Validators;

public class UpdateProfileRequestValidator : AbstractValidator<UpdateProfileRequest>
{
    public UpdateProfileRequestValidator()
    {
        RuleFor(x => x.DisplayName)
            .Length(1, 50).WithMessage("Display name must be between 1 and 50 characters.")
            .Must(name => name == null || !name.Any(char.IsControl)).WithMessage("Display name must not contain control characters.")
            .When(x => x.DisplayName is not null);

        RuleFor(x => x.ApnsToken)
            .MaximumLength(200).WithMessage("APNs token must not exceed 200 characters.")
            .When(x => x.ApnsToken is not null);
    }
}
