using HearHere.Shared.Data;
using HearHere.Shared.Services;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = FunctionsApplication.CreateBuilder(args);

var connectionString = builder.Configuration["Database:ConnectionString"]
    ?? throw new InvalidOperationException("Database:ConnectionString is not configured.");

builder.Services.AddDbContext<HearHereDbContext>(options =>
    options.UseNpgsql(connectionString, npgsql =>
        npgsql.UseNetTopologySuite()));

builder.Services.AddSingleton<IBlobStorageService, BlobStorageService>();

builder.Services.AddHttpClient("OpenAIModerationClient");
builder.Services.AddHttpClient("SpeechServiceClient");

builder.Build().Run();
