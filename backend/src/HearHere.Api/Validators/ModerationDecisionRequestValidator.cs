using FluentValidation;
using HearHere.Shared.Models.Requests;

namespace HearHere.Api.Validators;

public class ModerationDecisionRequestValidator : AbstractValidator<ModerationDecisionRequest>
{
    public ModerationDecisionRequestValidator()
    {
        RuleFor(x => x.Decision)
            .NotEmpty().WithMessage("Decision is required.")
            .Must(d => d is "approved" or "rejected")
            .WithMessage("Decision must be 'approved' or 'rejected'.");

        RuleFor(x => x.Notes)
            .MaximumLength(2000).WithMessage("Notes must not exceed 2000 characters.")
            .When(x => x.Notes is not null);
    }
}
