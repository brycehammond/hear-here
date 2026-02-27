using FluentValidation;
using HearHere.Shared.Models.Requests;

namespace HearHere.Api.Validators;

public class CreateReportRequestValidator : AbstractValidator<CreateReportRequest>
{
    private static readonly string[] ValidReasons =
    [
        "hate_speech", "harassment", "violence", "sexual_content",
        "spam", "misinformation", "other"
    ];

    public CreateReportRequestValidator()
    {
        RuleFor(x => x.RecordingId)
            .NotEmpty().WithMessage("Recording ID is required.");

        RuleFor(x => x.Reason)
            .NotEmpty().WithMessage("Reason is required.")
            .Must(r => ValidReasons.Contains(r))
            .WithMessage($"Reason must be one of: {string.Join(", ", ValidReasons)}.");

        RuleFor(x => x.Description)
            .MaximumLength(1000).WithMessage("Description must not exceed 1000 characters.")
            .When(x => x.Description is not null);
    }
}
