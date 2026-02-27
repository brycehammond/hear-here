using System.Text.Json;
using Microsoft.Azure.NotificationHubs;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace HearHere.Shared.Services;

public class NotificationHubsService : INotificationService
{
    private readonly NotificationHubClient _hubClient;
    private readonly ILogger<NotificationHubsService> _logger;

    public NotificationHubsService(IConfiguration configuration, ILogger<NotificationHubsService> logger)
    {
        var connectionString = configuration["Azure:NotificationHub:ConnectionString"]
            ?? throw new InvalidOperationException("Azure:NotificationHub:ConnectionString is not configured.");
        var hubName = configuration["Azure:NotificationHub:HubName"]
            ?? throw new InvalidOperationException("Azure:NotificationHub:HubName is not configured.");

        _hubClient = NotificationHubClient.CreateClientFromConnectionString(connectionString, hubName);
        _logger = logger;
    }

    public async Task SendPushNotificationAsync(string deviceToken, string title, string body, Dictionary<string, string>? customData = null)
    {
        var payload = new Dictionary<string, object>
        {
            ["aps"] = new Dictionary<string, object>
            {
                ["alert"] = new Dictionary<string, string>
                {
                    ["title"] = title,
                    ["body"] = body
                },
                ["sound"] = "default"
            }
        };

        if (customData is not null)
        {
            foreach (var (key, value) in customData)
            {
                payload[key] = value;
            }
        }

        var jsonPayload = JsonSerializer.Serialize(payload);
        var notification = new AppleNotification(jsonPayload);

        await _hubClient.SendDirectNotificationAsync(notification, deviceToken);

        _logger.LogInformation("Push notification sent to device token {DeviceToken}: {Title}", deviceToken[..8] + "...", title);
    }
}
