using System.Text.Json;
using Azure.Identity;
using Azure.Messaging.ServiceBus;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace HearHere.Shared.Services;

public class ServiceBusMessageQueueService : IMessageQueueService, IAsyncDisposable
{
    private readonly ServiceBusSender _sender;
    private readonly ServiceBusClient _client;
    private readonly ILogger<ServiceBusMessageQueueService> _logger;

    public ServiceBusMessageQueueService(IConfiguration configuration, ILogger<ServiceBusMessageQueueService> logger)
    {
        _logger = logger;

        var fullyQualifiedNamespace = configuration["Azure:ServiceBusNamespace"]
            ?? throw new InvalidOperationException("Azure:ServiceBusNamespace configuration is required.");
        var queueName = configuration["Azure:ServiceBusQueueName"] ?? "moderation-requests";

        _client = new ServiceBusClient(fullyQualifiedNamespace, new DefaultAzureCredential());
        _sender = _client.CreateSender(queueName);
    }

    public async Task SendModerationRequestAsync(Guid recordingId, CancellationToken cancellationToken = default)
    {
        var body = JsonSerializer.Serialize(new { recordingId });
        var message = new ServiceBusMessage(body)
        {
            ContentType = "application/json",
            Subject = "moderation-request",
            MessageId = $"moderation-{recordingId}"
        };

        await _sender.SendMessageAsync(message, cancellationToken);
        _logger.LogInformation("Sent moderation request for recording {RecordingId}", recordingId);
    }

    public async ValueTask DisposeAsync()
    {
        await _sender.DisposeAsync();
        await _client.DisposeAsync();
        GC.SuppressFinalize(this);
    }
}
