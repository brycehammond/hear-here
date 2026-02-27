using HearHere.Shared.Data;
using HearHere.Shared.Services;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Options;
using NSubstitute;

namespace HearHere.Api.Tests.Endpoints;

public class HearHereWebApplicationFactory : WebApplicationFactory<Program>
{
    private readonly string _dbName = $"HearHereTest_{Guid.NewGuid():N}";

    public IBlobStorageService BlobStorageMock { get; } = Substitute.For<IBlobStorageService>();
    public IMessageQueueService MessageQueueMock { get; } = Substitute.For<IMessageQueueService>();

    public HearHereWebApplicationFactory()
    {
        // Default mock setups
        BlobStorageMock.GenerateUploadSasUrl(Arg.Any<string>(), Arg.Any<TimeSpan>())
            .Returns((new Uri("https://test.blob.core.windows.net/test"), DateTimeOffset.UtcNow.AddMinutes(15)));

        BlobStorageMock.GenerateReadSasUrl(Arg.Any<string>(), Arg.Any<TimeSpan>())
            .Returns((new Uri("https://test.blob.core.windows.net/test-read"), DateTimeOffset.UtcNow.AddHours(1)));

        BlobStorageMock.BlobExistsAsync(Arg.Any<string>())
            .Returns(true);
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");

        builder.ConfigureTestServices(services =>
        {
            // Remove all EF Core / DbContext registrations to avoid "multiple providers" error
            var descriptorsToRemove = services
                .Where(d =>
                    d.ServiceType == typeof(DbContextOptions<HearHereDbContext>) ||
                    d.ServiceType == typeof(DbContextOptions) ||
                    d.ServiceType == typeof(HearHereDbContext) ||
                    (d.ServiceType.FullName?.Contains("EntityFrameworkCore") == true
                        && d.ServiceType.FullName?.Contains("InMemory") != true) ||
                    d.ServiceType.FullName?.Contains("Npgsql") == true)
                .ToList();
            foreach (var descriptor in descriptorsToRemove)
                services.Remove(descriptor);

            services.AddDbContext<HearHereDbContext>(options =>
                options.UseInMemoryDatabase(_dbName));

            // Replace blob storage and message queue
            services.RemoveAll<IBlobStorageService>();
            services.AddSingleton(BlobStorageMock);

            services.RemoveAll<IMessageQueueService>();
            services.AddSingleton(MessageQueueMock);

            // Replace auth
            services.RemoveAll<IConfigureOptions<AuthenticationOptions>>();
            services.AddAuthentication(options =>
                {
                    options.DefaultAuthenticateScheme = TestAuthHandler.SchemeName;
                    options.DefaultChallengeScheme = TestAuthHandler.SchemeName;
                })
                .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(
                    TestAuthHandler.SchemeName, _ => { });
        });
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            TestAuthHandler.AdditionalClaims.Clear();
        }

        base.Dispose(disposing);
    }
}
