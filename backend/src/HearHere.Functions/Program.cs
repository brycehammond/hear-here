using Azure.Identity;
using Azure.Extensions.AspNetCore.Configuration.Secrets;
using HearHere.Shared.Configuration;
using HearHere.Shared.Data;
using HearHere.Shared.Services;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
var builder = FunctionsApplication.CreateBuilder(args);

// -- Key Vault Configuration (non-Development only) --
var environment = Environment.GetEnvironmentVariable("AZURE_FUNCTIONS_ENVIRONMENT") ?? "Development";
if (environment != "Development")
{
    var keyVaultUri = builder.Configuration["KeyVault:Uri"];
    if (!string.IsNullOrEmpty(keyVaultUri))
    {
        builder.Configuration.AddAzureKeyVault(new Uri(keyVaultUri), new DefaultAzureCredential());
    }
}

var connectionString = builder.Configuration["Database:ConnectionString"]
    ?? throw new InvalidOperationException("Database:ConnectionString is not configured.");

if (environment == "Development")
{
    builder.Services.AddDbContext<HearHereDbContext>(options =>
        options.UseNpgsql(connectionString, npgsql =>
            npgsql.UseNetTopologySuite()));
}
else
{
    var dataSourceBuilder = new Npgsql.NpgsqlDataSourceBuilder(connectionString);
    Npgsql.NpgsqlNetTopologySuiteExtensions.UseNetTopologySuite(dataSourceBuilder);
    dataSourceBuilder.UsePeriodicPasswordProvider(async (_, ct) =>
    {
        var credential = new DefaultAzureCredential();
        var token = await credential.GetTokenAsync(
            new Azure.Core.TokenRequestContext(["https://ossrdbms-aad.database.windows.net/.default"]), ct);
        return token.Token;
    }, TimeSpan.FromMinutes(55), TimeSpan.FromSeconds(0));
    var dataSource = dataSourceBuilder.Build();
    builder.Services.AddDbContext<HearHereDbContext>(options =>
        options.UseNpgsql(dataSource, npgsql => npgsql.UseNetTopologySuite()));
}

builder.Services.AddSingleton<IBlobStorageService, BlobStorageService>();

builder.Services.AddHttpClient("OpenAIModerationClient");
builder.Services.AddHttpClient("SpeechServiceClient");

builder.Services.Configure<ModerationSettings>(builder.Configuration.GetSection(ModerationSettings.SectionName));

builder.Services.AddSingleton<INotificationService, NotificationHubsService>();

builder.Build().Run();
