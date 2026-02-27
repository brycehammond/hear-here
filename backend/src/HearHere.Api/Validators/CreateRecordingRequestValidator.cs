using FluentValidation;
using HearHere.Shared.Models.Requests;

namespace HearHere.Api.Validators;

public class CreateRecordingRequestValidator : AbstractValidator<CreateRecordingRequest>
{
    public CreateRecordingRequestValidator()
    {
        RuleFor(x => x.Subject)
            .NotEmpty().WithMessage("Subject is required.")
            .MaximumLength(200).WithMessage("Subject must not exceed 200 characters.");

        RuleFor(x => x.Description)
            .MaximumLength(2000).WithMessage("Description must not exceed 2000 characters.")
            .When(x => x.Description is not null);

        RuleFor(x => x.Latitude)
            .InclusiveBetween(-90, 90).WithMessage("Latitude must be between -90 and 90.");

        RuleFor(x => x.Longitude)
            .InclusiveBetween(-180, 180).WithMessage("Longitude must be between -180 and 180.");

        RuleFor(x => x.DurationSec)
            .InclusiveBetween(1, 300).WithMessage("Duration must be between 1 and 300 seconds.");
    }
}
