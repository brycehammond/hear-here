using Azure.Storage.Blobs.Models;

namespace HearHere.Shared.Services;

public interface IBlobStorageService
{
    Task<(Uri Url, DateTimeOffset ExpiresAt)> GenerateUploadSasUrl(string blobName, TimeSpan expiry);
    Task<(Uri Url, DateTimeOffset ExpiresAt)> GenerateReadSasUrl(string blobName, TimeSpan expiry);
    Task<bool> BlobExistsAsync(string blobName);
    Task DeleteBlobAsync(string blobName);
    Task<BlobProperties?> GetBlobPropertiesAsync(string blobName);
    Task<byte[]> DownloadBlobRangeAsync(string blobName, long offset, int count);
}
