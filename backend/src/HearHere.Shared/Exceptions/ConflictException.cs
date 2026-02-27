namespace HearHere.Shared.Exceptions;

public class ConflictException : Exception
{
    public string ErrorCode => "CONFLICT";

    public ConflictException(string message) : base(message)
    {
    }
}
