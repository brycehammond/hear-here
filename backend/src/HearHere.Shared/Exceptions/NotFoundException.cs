namespace HearHere.Shared.Exceptions;

public class NotFoundException : Exception
{
    public string ErrorCode => "NOT_FOUND";

    public NotFoundException(string message) : base(message)
    {
    }
}
