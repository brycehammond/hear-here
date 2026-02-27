using System.Net.Http.Json;
using System.Text.Json;
using HearHere.Shared.Data;
using Microsoft.Azure.Functions.Worker;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace HearHere.Functions.Functions;

public class ClassificationActivity
{
    private readonly HearHereDbContext _db;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IConfiguration _configuration;

    public ClassificationActivity(
        HearHereDbContext db,
        IHttpClientFactory httpClientFactory,
        IConfiguration configuration)
    {
        _db = db;
        _httpClientFactory = httpClientFactory;
        _configuration = configuration;
    }

    [Function(nameof(ClassifyContent))]
    public async Task<string> ClassifyContent(
        [ActivityTrigger] ClassifyInput input,
        FunctionContext executionContext)
    {
        var logger = executionContext.GetLogger(nameof(ClassifyContent));
        logger.LogInformation("Classifying content for recording {RecordingId}", input.RecordingId);

        var apiKey = _configuration["OpenAI:ApiKey"]
            ?? throw new InvalidOperationException("OpenAI:ApiKey is not configured.");
        var model = _configuration["OpenAI:ModerationModel"] ?? "omni-moderation-latest";

        var client = _httpClientFactory.CreateClient("OpenAIModerationClient");
        client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", apiKey);

        var requestBody = new
        {
            model,
            input = input.Transcript
        };

        var response = await client.PostAsJsonAsync(
            "https://api.openai.com/v1/moderations",
            requestBody);

        response.EnsureSuccessStatusCode();

        var result = await response.Content.ReadFromJsonAsync<JsonElement>();
        var moderationResult = result.GetProperty("results")[0];

        // Extract category scores
        var categoryScores = moderationResult.GetProperty("category_scores");
        var scoresJson = categoryScores.GetRawText();

        // Store raw moderation scores in DB
        var recording = await _db.Recordings.FirstOrDefaultAsync(r => r.Id == input.RecordingId)
            ?? throw new InvalidOperationException($"Recording {input.RecordingId} not found");

        recording.ModerationScores = scoresJson;
        recording.UpdatedAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync();

        logger.LogInformation("Stored moderation scores for recording {RecordingId}", input.RecordingId);

        return scoresJson;
    }
}
