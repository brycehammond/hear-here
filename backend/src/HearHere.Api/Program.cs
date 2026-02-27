using System.Text.Json;
using FluentValidation;
using HearHere.Api.Endpoints;
using HearHere.Api.Middleware;
using HearHere.Shared.Data;
using HearHere.Shared.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Identity.Web;

var builder = WebApplication.CreateBuilder(args);

// -- Authentication: Microsoft Entra External ID (Azure AD B2C) --
builder.Services.AddMicrosoftIdentityWebApiAuthentication(builder.Configuration, "AzureAdB2C");

// -- Authorization --
builder.Services.AddAuthorizationBuilder()
    .AddPolicy("AdminOnly", policy => policy.RequireClaim("extension_Role", "admin"));

// -- Database --
builder.Services.AddDbContext<HearHereDbContext>(options =>
    options.UseNpgsql(
        builder.Configuration.GetConnectionString("DefaultConnection"),
        npgsqlOptions => npgsqlOptions.UseNetTopologySuite()));

// -- FluentValidation --
builder.Services.AddValidatorsFromAssemblyContaining<Program>();

// -- Blob Storage --
builder.Services.AddSingleton<IBlobStorageService, BlobStorageService>();

// -- JSON serialization --
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower;
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

// -- Map endpoints --
app.MapAuthEndpoints();
app.MapUserEndpoints();
app.MapRecordingEndpoints();
app.MapDiscoveryEndpoints();
app.MapReportEndpoints();
app.MapAdminEndpoints();

// -- Health check --
app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));

app.Run();

// Make the implicit Program class public so test projects can reference it
public partial class Program { }
