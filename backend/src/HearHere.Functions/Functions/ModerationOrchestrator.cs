using Microsoft.Azure.Functions.Worker;
using Microsoft.DurableTask;
using Microsoft.DurableTask.Client;
using Microsoft.Extensions.Logging;

namespace HearHere.Functions.Functions;

public static class ModerationOrchestrator
{
    [Function(nameof(RunModerationPipeline))]
    public static async Task RunModerationPipeline(
        [OrchestrationTrigger] TaskOrchestrationContext context)
    {
        var logger = context.CreateReplaySafeLogger(nameof(ModerationOrchestrator));
        var recordingId = context.GetInput<Guid>();

        logger.LogInformation("Starting moderation pipeline for recording {RecordingId}", recordingId);

        // Step 1: Start batch transcription
        var transcriptionJobUrl = await context.CallActivityAsync<string>(
            nameof(TranscriptionActivity.StartTranscription),
            recordingId);

        // Step 2: Poll for transcription completion (30s intervals)
        while (true)
        {
            var status = await context.CallActivityAsync<string>(
                nameof(TranscriptionActivity.CheckTranscription),
                transcriptionJobUrl);

            if (status == "Succeeded")
            {
                break;
            }

            if (status == "Failed")
            {
                logger.LogWarning("Transcription failed for recording {RecordingId}, routing to human review", recordingId);
                await context.CallActivityAsync(
                    nameof(DecisionActivity.ApplyDecision),
                    new DecisionInput(recordingId, "HUMAN_REVIEW", "transcription_failed"));
                await context.WaitForExternalEvent<string>("moderationDecision");
                await context.CallActivityAsync(
                    nameof(NotificationActivity.SendNotification),
                    recordingId);
                return;
            }

            // Wait 30 seconds before checking again
            var nextCheck = context.CurrentUtcDateTime.AddSeconds(30);
            await context.CreateTimer(nextCheck, CancellationToken.None);
        }

        // Step 3: Store transcript in DB
        var transcript = await context.CallActivityAsync<string>(
            nameof(TranscriptionActivity.StoreTranscript),
            new StoreTranscriptInput(recordingId, transcriptionJobUrl));

        // Step 4: Classify content via OpenAI Moderation API
        var moderationScores = await context.CallActivityAsync<string>(
            nameof(ClassificationActivity.ClassifyContent),
            new ClassifyInput(recordingId, transcript));

        // Step 5: Evaluate decision based on thresholds
        var decision = await context.CallActivityAsync<string>(
            nameof(DecisionActivity.EvaluateDecision),
            new EvaluateDecisionInput(recordingId, moderationScores));

        // Step 6: Branch based on decision
        if (decision == "HUMAN_REVIEW")
        {
            await context.CallActivityAsync(
                nameof(DecisionActivity.ApplyDecision),
                new DecisionInput(recordingId, "HUMAN_REVIEW", "uncertain_score"));

            logger.LogInformation("Recording {RecordingId} routed to human review, waiting for external event", recordingId);

            var humanDecision = await context.WaitForExternalEvent<string>("moderationDecision");

            await context.CallActivityAsync(
                nameof(DecisionActivity.ApplyHumanDecision),
                new HumanDecisionInput(recordingId, humanDecision));
        }
        else
        {
            await context.CallActivityAsync(
                nameof(DecisionActivity.ApplyDecision),
                new DecisionInput(recordingId, decision, null));
        }

        // Step 7: Notify user
        await context.CallActivityAsync(
            nameof(NotificationActivity.SendNotification),
            recordingId);

        logger.LogInformation("Moderation pipeline completed for recording {RecordingId}", recordingId);
    }

    [Function(nameof(StartModerationFromServiceBus))]
    public static async Task StartModerationFromServiceBus(
        [ServiceBusTrigger("moderation-requests", Connection = "ServiceBusConnection")] Guid recordingId,
        [DurableClient] DurableTaskClient client,
        FunctionContext executionContext)
    {
        var logger = executionContext.GetLogger(nameof(StartModerationFromServiceBus));
        logger.LogInformation("Received moderation request for recording {RecordingId}", recordingId);

        var instanceId = $"moderation-{recordingId}";
        await client.ScheduleNewOrchestrationInstanceAsync(
            nameof(RunModerationPipeline),
            recordingId,
            new StartOrchestrationOptions { InstanceId = instanceId });

        logger.LogInformation("Started orchestration {InstanceId} for recording {RecordingId}", instanceId, recordingId);
    }
}

public record StoreTranscriptInput(Guid RecordingId, string TranscriptionJobUrl);
public record ClassifyInput(Guid RecordingId, string Transcript);
public record EvaluateDecisionInput(Guid RecordingId, string ModerationScoresJson);
public record DecisionInput(Guid RecordingId, string Decision, string? Reason);
public record HumanDecisionInput(Guid RecordingId, string Decision);
