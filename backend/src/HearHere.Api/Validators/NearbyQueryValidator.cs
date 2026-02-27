using FluentValidation;

namespace HearHere.Api.Validators;

public class NearbyQuery
{
    public double Lat { get; init; }
    public double Lng { get; init; }
    public int Radius { get; init; } = 500;
    public int Limit { get; init; } = 20;
    public string? Cursor { get; init; }
}

public class NearbyQueryValidator : AbstractValidator<NearbyQuery>
{
    public NearbyQueryValidator()
    {
        RuleFor(x => x.Lat)
            .InclusiveBetween(-90, 90).WithMessage("Latitude must be between -90 and 90.");

        RuleFor(x => x.Lng)
            .InclusiveBetween(-180, 180).WithMessage("Longitude must be between -180 and 180.");

        RuleFor(x => x.Radius)
            .InclusiveBetween(50, 5000).WithMessage("Radius must be between 50 and 5000 meters.");

        RuleFor(x => x.Limit)
            .InclusiveBetween(1, 50).WithMessage("Limit must be between 1 and 50.");
    }
}
