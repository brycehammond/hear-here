namespace HearHere.Shared.Exceptions;

public class ForbiddenException : Exception
{
    public string ErrorCode => "FORBIDDEN";

    public ForbiddenException(string message) : base(message)
    {
    }
}
