using System.Text.Json;
using Azure.Identity;
using FluentValidation;
using HearHere.Api.Endpoints;
using HearHere.Api.Middleware;
using HearHere.Shared.Data;
using HearHere.Shared.Services;
using Microsoft.AspNetCore.OpenApi;
using Microsoft.EntityFrameworkCore;
using Microsoft.Identity.Web;
using Microsoft.OpenApi;
using Scalar.AspNetCore;
var builder = WebApplication.CreateBuilder(args);

// -- Key Vault Configuration (non-Development only) --
if (!builder.Environment.IsDevelopment())
{
    var keyVaultUri = builder.Configuration["KeyVault:Uri"];
    if (!string.IsNullOrEmpty(keyVaultUri))
    {
        builder.Configuration.AddAzureKeyVault(new Uri(keyVaultUri), new DefaultAzureCredential());
    }
}

// -- Authentication: Microsoft Entra External ID (Azure AD B2C) --
builder.Services.AddMicrosoftIdentityWebApiAuthentication(builder.Configuration, "AzureAdB2C");

// -- Authorization --
builder.Services.AddAuthorizationBuilder()
    .AddPolicy("AdminOnly", policy => policy.RequireClaim("extension_Role", "admin"));

// -- Database --
if (builder.Environment.IsDevelopment())
{
    builder.Services.AddDbContext<HearHereDbContext>(options =>
        options.UseNpgsql(
            builder.Configuration.GetConnectionString("DefaultConnection"),
            npgsqlOptions => npgsqlOptions.UseNetTopologySuite()));
}
else
{
    var connectionString = builder.Configuration.GetConnectionString("DefaultConnection")
        ?? throw new InvalidOperationException("ConnectionStrings:DefaultConnection is not configured.");
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
        options.UseNpgsql(dataSource, npgsqlOptions => npgsqlOptions.UseNetTopologySuite()));
}

// -- FluentValidation --
builder.Services.AddValidatorsFromAssemblyContaining<Program>();

// -- Blob Storage --
builder.Services.AddSingleton<IBlobStorageService, BlobStorageService>();

// -- Service Bus --
builder.Services.AddSingleton<IMessageQueueService, ServiceBusMessageQueueService>();

// -- JSON serialization --
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower;
});

// -- OpenAPI --
builder.Services.AddOpenApi(options =>
{
    options.AddDocumentTransformer((document, context, cancellationToken) =>
    {
        document.Info = new OpenApiInfo
        {
            Title = "HearHere API",
            Version = "v1"
        };

        var components = document.Components ??= new OpenApiComponents();
        components.SecuritySchemes ??= new Dictionary<string, IOpenApiSecurityScheme>();
        components.SecuritySchemes["Bearer"] = new OpenApiSecurityScheme
        {
            Type = SecuritySchemeType.Http,
            Scheme = "bearer",
            BearerFormat = "JWT",
            Description = "Enter your JWT token"
        };

        return Task.CompletedTask;
    });
});

// -- CORS --
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        if (builder.Environment.IsDevelopment())
        {
            policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod();
        }
        else
        {
            policy.WithOrigins(
                    builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [])
                .AllowAnyHeader()
                .AllowAnyMethod();
        }
    });
});

var app = builder.Build();

// -- Middleware pipeline --
app.UseMiddleware<ErrorHandlingMiddleware>();
app.UseCors();
app.UseAuthentication();
app.UseAuthorization();

// -- OpenAPI + Scalar UI (Development only) --
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference();
}

// -- Map endpoints --
app.MapAuthEndpoints();
app.MapUserEndpoints();
app.MapRecordingEndpoints();
app.MapDiscoveryEndpoints();
app.MapReportEndpoints();
app.MapAdminEndpoints();

// -- Health check --
app.MapGet("/health", () => Results.Ok(new { status = "healthy" }))
    .ExcludeFromDescription();

app.Run();

// Make the implicit Program class public so test projects can reference it
public partial class Program { }
