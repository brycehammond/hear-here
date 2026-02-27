using Azure.Identity;
using Azure.Storage;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Sas;
using Microsoft.Extensions.Configuration;

namespace HearHere.Shared.Services;

public class BlobStorageService : IBlobStorageService
{
    private readonly BlobServiceClient _blobServiceClient;
    private readonly string _containerName;

    public BlobStorageService(IConfiguration configuration)
    {
        var accountName = configuration["Azure:StorageAccountName"]
            ?? throw new InvalidOperationException("Azure:StorageAccountName is not configured.");
        _containerName = configuration["Azure:StorageContainerName"]
            ?? throw new InvalidOperationException("Azure:StorageContainerName is not configured.");

        var serviceUri = new Uri($"https://{accountName}.blob.core.windows.net");
        _blobServiceClient = new BlobServiceClient(serviceUri, new DefaultAzureCredential());
    }

    public async Task<(Uri Url, DateTimeOffset ExpiresAt)> GenerateUploadSasUrl(string blobName, TimeSpan expiry)
    {
        var expiresAt = DateTimeOffset.UtcNow.Add(expiry);

        var delegationKey = await _blobServiceClient.GetUserDelegationKeyAsync(
            DateTimeOffset.UtcNow.AddMinutes(-5),
            expiresAt);

        var sasBuilder = new BlobSasBuilder
        {
            BlobContainerName = _containerName,
            BlobName = blobName,
            Resource = "b",
            StartsOn = DateTimeOffset.UtcNow.AddMinutes(-5),
            ExpiresOn = expiresAt
        };
        sasBuilder.SetPermissions(BlobSasPermissions.Write | BlobSasPermissions.Create);

        var blobUriBuilder = new BlobUriBuilder(_blobServiceClient.Uri)
        {
            BlobContainerName = _containerName,
            BlobName = blobName,
            Sas = sasBuilder.ToSasQueryParameters(delegationKey.Value, _blobServiceClient.AccountName)
        };

        return (blobUriBuilder.ToUri(), expiresAt);
    }

    public async Task<(Uri Url, DateTimeOffset ExpiresAt)> GenerateReadSasUrl(string blobName, TimeSpan expiry)
    {
        var expiresAt = DateTimeOffset.UtcNow.Add(expiry);

        var delegationKey = await _blobServiceClient.GetUserDelegationKeyAsync(
            DateTimeOffset.UtcNow.AddMinutes(-5),
            expiresAt);

        var sasBuilder = new BlobSasBuilder
        {
            BlobContainerName = _containerName,
            BlobName = blobName,
            Resource = "b",
            StartsOn = DateTimeOffset.UtcNow.AddMinutes(-5),
            ExpiresOn = expiresAt
        };
        sasBuilder.SetPermissions(BlobSasPermissions.Read);

        var blobUriBuilder = new BlobUriBuilder(_blobServiceClient.Uri)
        {
            BlobContainerName = _containerName,
            BlobName = blobName,
            Sas = sasBuilder.ToSasQueryParameters(delegationKey.Value, _blobServiceClient.AccountName)
        };

        return (blobUriBuilder.ToUri(), expiresAt);
    }

    public async Task<bool> BlobExistsAsync(string blobName)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(_containerName);
        var blobClient = containerClient.GetBlobClient(blobName);
        var response = await blobClient.ExistsAsync();
        return response.Value;
    }

    public async Task DeleteBlobAsync(string blobName)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(_containerName);
        var blobClient = containerClient.GetBlobClient(blobName);
        await blobClient.DeleteIfExistsAsync(DeleteSnapshotsOption.IncludeSnapshots);
    }

    public async Task<BlobProperties?> GetBlobPropertiesAsync(string blobName)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(_containerName);
        var blobClient = containerClient.GetBlobClient(blobName);

        if (!await blobClient.ExistsAsync())
            return null;

        var response = await blobClient.GetPropertiesAsync();
        return response.Value;
    }
}
