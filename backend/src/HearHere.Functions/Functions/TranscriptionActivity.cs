using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using HearHere.Shared.Data;
using HearHere.Shared.Services;
using Microsoft.Azure.Functions.Worker;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace HearHere.Functions.Functions;

public class TranscriptionActivity
{
    private readonly HearHereDbContext _db;
    private readonly IBlobStorageService _blobStorage;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IConfiguration _configuration;

    public TranscriptionActivity(
        HearHereDbContext db,
        IBlobStorageService blobStorage,
        IHttpClientFactory httpClientFactory,
        IConfiguration configuration)
    {
        _db = db;
        _blobStorage = blobStorage;
        _httpClientFactory = httpClientFactory;
        _configuration = configuration;
    }

    [Function(nameof(StartTranscription))]
    public async Task<string> StartTranscription(
        [ActivityTrigger] Guid recordingId,
        FunctionContext executionContext)
    {
        var logger = executionContext.GetLogger(nameof(StartTranscription));
        logger.LogInformation("Starting transcription for recording {RecordingId}", recordingId);

        var recording = await _db.Recordings.FirstOrDefaultAsync(r => r.Id == recordingId)
            ?? throw new InvalidOperationException($"Recording {recordingId} not found");

        // Generate a read SAS URL for the audio blob
        var (audioBlobUrl, _) = await _blobStorage.GenerateReadSasUrl(recording.AudioBlobKey, TimeSpan.FromHours(4));

        var speechKey = _configuration["Azure:SpeechServiceKey"]
            ?? throw new InvalidOperationException("Azure:SpeechServiceKey is not configured.");
        var speechRegion = _configuration["Azure:SpeechServiceRegion"]
            ?? throw new InvalidOperationException("Azure:SpeechServiceRegion is not configured.");

        // Create batch transcription job via Azure AI Speech REST API
        var client = _httpClientFactory.CreateClient("SpeechServiceClient");
        client.DefaultRequestHeaders.Add("Ocp-Apim-Subscription-Key", speechKey);

        var requestBody = new
        {
            contentUrls = new[] { audioBlobUrl.ToString() },
            locale = "en-US",
            displayName = $"moderation-{recordingId}",
            properties = new
            {
                wordLevelTimestampsEnabled = false,
                diarizationEnabled = false,
                punctuationMode = "DictatedAndAutomatic",
                profanityFilterMode = "None"
            }
        };

        var response = await client.PostAsJsonAsync(
            $"https://{speechRegion}.api.cognitive.microsoft.com/speechtotext/v3.2/transcriptions",
            requestBody);

        response.EnsureSuccessStatusCode();

        var result = await response.Content.ReadFromJsonAsync<JsonElement>();
        var transcriptionUrl = result.GetProperty("self").GetString()!;

        logger.LogInformation("Transcription job created at {TranscriptionUrl} for recording {RecordingId}",
            transcriptionUrl, recordingId);

        return transcriptionUrl;
    }

    [Function(nameof(CheckTranscription))]
    public async Task<string> CheckTranscription(
        [ActivityTrigger] string transcriptionJobUrl,
        FunctionContext executionContext)
    {
        var logger = executionContext.GetLogger(nameof(CheckTranscription));

        var speechKey = _configuration["Azure:SpeechServiceKey"]
            ?? throw new InvalidOperationException("Azure:SpeechServiceKey is not configured.");

        var client = _httpClientFactory.CreateClient("SpeechServiceClient");
        client.DefaultRequestHeaders.Add("Ocp-Apim-Subscription-Key", speechKey);

        var response = await client.GetFromJsonAsync<JsonElement>(transcriptionJobUrl);
        var status = response.GetProperty("status").GetString()!;

        logger.LogInformation("Transcription job status: {Status}", status);

        // Azure AI Speech statuses: NotStarted, Running, Succeeded, Failed
        return status;
    }

    [Function(nameof(StoreTranscript))]
    public async Task<string> StoreTranscript(
        [ActivityTrigger] StoreTranscriptInput input,
        FunctionContext executionContext)
    {
        var logger = executionContext.GetLogger(nameof(StoreTranscript));

        var speechKey = _configuration["Azure:SpeechServiceKey"]
            ?? throw new InvalidOperationException("Azure:SpeechServiceKey is not configured.");

        var client = _httpClientFactory.CreateClient("SpeechServiceClient");
        client.DefaultRequestHeaders.Add("Ocp-Apim-Subscription-Key", speechKey);

        // Get transcription files
        var filesResponse = await client.GetFromJsonAsync<JsonElement>($"{input.TranscriptionJobUrl}/files");
        var files = filesResponse.GetProperty("values");

        string transcript = string.Empty;

        foreach (var file in files.EnumerateArray())
        {
            if (file.GetProperty("kind").GetString() == "Transcription")
            {
                var contentUrl = file.GetProperty("links").GetProperty("contentUrl").GetString()!;
                var transcriptionResult = await client.GetFromJsonAsync<JsonElement>(contentUrl);

                // Extract combined recognized phrases
                var combinedPhrases = transcriptionResult.GetProperty("combinedRecognizedPhrases");
                var phrases = new List<string>();
                foreach (var phrase in combinedPhrases.EnumerateArray())
                {
                    phrases.Add(phrase.GetProperty("display").GetString() ?? string.Empty);
                }
                transcript = string.Join(" ", phrases);
                break;
            }
        }

        // Store transcript in DB
        var recording = await _db.Recordings.FirstOrDefaultAsync(r => r.Id == input.RecordingId)
            ?? throw new InvalidOperationException($"Recording {input.RecordingId} not found");

        recording.Transcript = transcript;
        recording.UpdatedAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync();

        logger.LogInformation("Stored transcript ({Length} chars) for recording {RecordingId}",
            transcript.Length, input.RecordingId);

        return transcript;
    }
}
