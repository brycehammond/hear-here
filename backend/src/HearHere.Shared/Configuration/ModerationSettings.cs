namespace HearHere.Shared.Configuration;

public class ModerationSettings
{
    public const string SectionName = "Moderation";

    public Dictionary<string, CategoryThreshold> Thresholds { get; set; } = new()
    {
        ["hate"] = new(0.3, 0.7),
        ["hate/threatening"] = new(0.2, 0.5),
        ["harassment"] = new(0.3, 0.7),
        ["harassment/threatening"] = new(0.3, 0.7),
        ["self-harm"] = new(0.2, 0.5),
        ["self-harm/intent"] = new(0.2, 0.5),
        ["self-harm/instructions"] = new(0.2, 0.5),
        ["sexual"] = new(0.3, 0.7),
        ["sexual/minors"] = new(0.2, 0.5),
        ["violence"] = new(0.3, 0.7),
        ["violence/graphic"] = new(0.3, 0.7),
    };

    public CategoryThreshold DefaultThreshold { get; set; } = new(0.3, 0.7);
}

public record CategoryThreshold(double ApproveBelow, double RejectAbove);
