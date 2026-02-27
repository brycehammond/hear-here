namespace HearHere.Shared.Services;

public interface IMessageQueueService
{
    Task SendModerationRequestAsync(Guid recordingId, CancellationToken cancellationToken = default);
}
