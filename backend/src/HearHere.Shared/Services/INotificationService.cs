namespace HearHere.Shared.Services;

public interface INotificationService
{
    Task SendPushNotificationAsync(string deviceToken, string title, string body, Dictionary<string, string>? customData = null);
}
