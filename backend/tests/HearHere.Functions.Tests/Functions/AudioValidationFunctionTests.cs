using Azure.Messaging.EventGrid;
using Azure.Storage.Blobs.Models;
using FluentAssertions;
using HearHere.Functions.Functions;
using HearHere.Shared.Data;
using HearHere.Shared.Data.Entities;
using HearHere.Shared.Services;
using Microsoft.Azure.Functions.Worker;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using NSubstitute;
using Xunit;

namespace HearHere.Functions.Tests.Functions;

public class AudioValidationFunctionTests
{
    private readonly HearHereDbContext _db;
    private readonly IBlobStorageService _blobStorage;
    private readonly AudioValidationFunction _sut;
    private readonly FunctionContext _functionContext;

    public AudioValidationFunctionTests()
    {
        var options = new DbContextOptionsBuilder<HearHereDbContext>()
            .UseInMemoryDatabase($"AudioValidation_{Guid.NewGuid()}")
            .Options;
        _db = new HearHereDbContext(options);

        _blobStorage = Substitute.For<IBlobStorageService>();
        _sut = new AudioValidationFunction(_db, _blobStorage);

        _functionContext = Substitute.For<FunctionContext>();
        var serviceProvider = Substitute.For<IServiceProvider>();
        _functionContext.InstanceServices.Returns(serviceProvider);
        var loggerFactory = Substitute.For<ILoggerFactory>();
        loggerFactory.CreateLogger(Arg.Any<string>()).Returns(Substitute.For<ILogger>());
        serviceProvider.GetService(typeof(ILoggerFactory)).Returns(loggerFactory);
    }

    private static EventGridEvent CreateEventGridEvent(string blobName = "recordings/test.aac")
    {
        return new EventGridEvent(
            subject: $"/blobServices/default/containers/recordings/blobs/{blobName}",
            eventType: "Microsoft.Storage.BlobCreated",
            dataVersion: "1.0",
            data: BinaryData.FromObjectAsJson(new { }));
    }

    private Recording CreateRecording(string blobKey = "recordings/test.aac", int durationSec = 60, string status = "pending_moderation")
    {
        return new Recording
        {
            Id = Guid.NewGuid(),
            UserId = Guid.NewGuid(),
            Subject = "Test",
            Status = status,
            AudioBlobKey = blobKey,
            DurationSec = durationSec,
            Location = new NetTopologySuite.Geometries.Point(0, 0) { SRID = 4326 },
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
    }

    private static byte[] CreateValidM4aHeader()
    {
        // M4A/MP4 ftyp header: 4 bytes size + "ftyp" + padding
        return [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x41, 0x20];
    }

    private static byte[] CreateValidAacAdtsHeader()
    {
        // AAC ADTS sync word: 0xFF 0xF1
        return [0xFF, 0xF1, 0x50, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
    }

    private static byte[] CreateM4aWithMvhd(double durationSeconds)
    {
        // Build a minimal M4A-like byte array with an ftyp header and mvhd atom
        var data = new byte[256];

        // ftyp at bytes 4-7
        data[4] = (byte)'f';
        data[5] = (byte)'t';
        data[6] = (byte)'y';
        data[7] = (byte)'p';

        // mvhd atom at offset 32
        int offset = 32;
        data[offset] = (byte)'m';
        data[offset + 1] = (byte)'v';
        data[offset + 2] = (byte)'h';
        data[offset + 3] = (byte)'d';

        // version 0
        data[offset + 4] = 0;

        // timescale = 1000 at offset+12
        uint timescale = 1000;
        data[offset + 12] = (byte)((timescale >> 24) & 0xFF);
        data[offset + 13] = (byte)((timescale >> 16) & 0xFF);
        data[offset + 14] = (byte)((timescale >> 8) & 0xFF);
        data[offset + 15] = (byte)(timescale & 0xFF);

        // duration in timescale units at offset+16
        uint duration = (uint)(durationSeconds * timescale);
        data[offset + 16] = (byte)((duration >> 24) & 0xFF);
        data[offset + 17] = (byte)((duration >> 16) & 0xFF);
        data[offset + 18] = (byte)((duration >> 8) & 0xFF);
        data[offset + 19] = (byte)(duration & 0xFF);

        return data;
    }

    private void SetupBlobProperties(long contentLength)
    {
        var blobProperties = BlobsModelFactory.BlobProperties(contentLength: contentLength);
        _blobStorage.GetBlobPropertiesAsync(Arg.Any<string>()).Returns(blobProperties);
    }

    [Fact]
    public async Task ValidFile_PassesValidation()
    {
        var recording = CreateRecording(durationSec: 60);
        _db.Recordings.Add(recording);
        await _db.SaveChangesAsync();

        SetupBlobProperties(1024 * 1024); // 1MB
        var m4aData = CreateM4aWithMvhd(60.0);
        _blobStorage.DownloadBlobRangeAsync(Arg.Any<string>(), 0, 12).Returns(CreateValidM4aHeader());
        _blobStorage.DownloadBlobRangeAsync(Arg.Any<string>(), 0, 256 * 1024).Returns(m4aData);

        await _sut.ValidateAudio(CreateEventGridEvent(), _functionContext);

        var result = await _db.Recordings.FindAsync(recording.Id);
        result!.Status.Should().Be("pending_moderation");
        (await _db.ModerationRecords.AnyAsync(m => m.RecordingId == recording.Id)).Should().BeFalse();
    }

    [Fact]
    public async Task OversizedFile_RejectsRecording()
    {
        var recording = CreateRecording();
        _db.Recordings.Add(recording);
        await _db.SaveChangesAsync();

        SetupBlobProperties(11 * 1024 * 1024); // 11MB, over 10MB limit

        await _sut.ValidateAudio(CreateEventGridEvent(), _functionContext);

        var result = await _db.Recordings.FindAsync(recording.Id);
        result!.Status.Should().Be("rejected");

        var modRecord = await _db.ModerationRecords.FirstOrDefaultAsync(m => m.RecordingId == recording.Id);
        modRecord.Should().NotBeNull();
        modRecord!.Action.Should().Be("auto_reject");
        modRecord.FromStatus.Should().Be("pending_moderation");
        modRecord.ToStatus.Should().Be("rejected");
        modRecord.Reason.Should().Contain("exceeds maximum");
    }

    [Fact]
    public async Task InvalidHeader_RejectsRecording()
    {
        var recording = CreateRecording();
        _db.Recordings.Add(recording);
        await _db.SaveChangesAsync();

        SetupBlobProperties(1024 * 1024);
        var invalidHeader = new byte[] { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B };
        _blobStorage.DownloadBlobRangeAsync(Arg.Any<string>(), 0, 12).Returns(invalidHeader);

        await _sut.ValidateAudio(CreateEventGridEvent(), _functionContext);

        var result = await _db.Recordings.FindAsync(recording.Id);
        result!.Status.Should().Be("rejected");

        var modRecord = await _db.ModerationRecords.FirstOrDefaultAsync(m => m.RecordingId == recording.Id);
        modRecord.Should().NotBeNull();
        modRecord!.Reason.Should().Contain("Invalid audio format");
    }

    [Fact]
    public async Task DurationMismatch_RejectsRecording()
    {
        var recording = CreateRecording(durationSec: 60);
        _db.Recordings.Add(recording);
        await _db.SaveChangesAsync();

        SetupBlobProperties(1024 * 1024);
        _blobStorage.DownloadBlobRangeAsync(Arg.Any<string>(), 0, 12).Returns(CreateValidM4aHeader());

        // Actual duration is 30s, declared is 60s -- difference of 30s
        var m4aData = CreateM4aWithMvhd(30.0);
        _blobStorage.DownloadBlobRangeAsync(Arg.Any<string>(), 0, 256 * 1024).Returns(m4aData);

        await _sut.ValidateAudio(CreateEventGridEvent(), _functionContext);

        var result = await _db.Recordings.FindAsync(recording.Id);
        result!.Status.Should().Be("rejected");

        var modRecord = await _db.ModerationRecords.FirstOrDefaultAsync(m => m.RecordingId == recording.Id);
        modRecord.Should().NotBeNull();
        modRecord!.Reason.Should().Contain("Duration mismatch");
    }

    [Fact]
    public async Task OrphanBlob_HandledGracefully()
    {
        // No recording in DB for this blob
        var act = () => _sut.ValidateAudio(CreateEventGridEvent("recordings/orphan.aac"), _functionContext);

        await act.Should().NotThrowAsync();

        // No blob operations should have been attempted
        await _blobStorage.DidNotReceiveWithAnyArgs().GetBlobPropertiesAsync(Arg.Any<string>());
    }

    [Fact]
    public async Task WithinTolerance_PassesValidation()
    {
        var recording = CreateRecording(durationSec: 60);
        _db.Recordings.Add(recording);
        await _db.SaveChangesAsync();

        SetupBlobProperties(1024 * 1024);
        _blobStorage.DownloadBlobRangeAsync(Arg.Any<string>(), 0, 12).Returns(CreateValidM4aHeader());

        // Actual duration is 57s, declared is 60s -- difference of 3s, within 5s tolerance
        var m4aData = CreateM4aWithMvhd(57.0);
        _blobStorage.DownloadBlobRangeAsync(Arg.Any<string>(), 0, 256 * 1024).Returns(m4aData);

        await _sut.ValidateAudio(CreateEventGridEvent(), _functionContext);

        var result = await _db.Recordings.FindAsync(recording.Id);
        result!.Status.Should().Be("pending_moderation");
        (await _db.ModerationRecords.AnyAsync(m => m.RecordingId == recording.Id)).Should().BeFalse();
    }

    [Fact]
    public void ExtractBlobName_ParsesCorrectly()
    {
        var result = AudioValidationFunction.ExtractBlobName(
            "/blobServices/default/containers/recordings/blobs/recordings/test.aac");

        result.Should().Be("recordings/test.aac");
    }

    [Fact]
    public void ExtractBlobName_ReturnsSubject_WhenNoBlobsSegment()
    {
        var result = AudioValidationFunction.ExtractBlobName("some-other-format");

        result.Should().Be("some-other-format");
    }

    [Fact]
    public void IsValidAudioHeader_AacAdts_ReturnsTrue()
    {
        var header = CreateValidAacAdtsHeader();
        AudioValidationFunction.IsValidAudioHeader(header).Should().BeTrue();
    }

    [Fact]
    public void IsValidAudioHeader_M4a_ReturnsTrue()
    {
        var header = CreateValidM4aHeader();
        AudioValidationFunction.IsValidAudioHeader(header).Should().BeTrue();
    }

    [Fact]
    public void IsValidAudioHeader_InvalidBytes_ReturnsFalse()
    {
        var header = new byte[] { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07 };
        AudioValidationFunction.IsValidAudioHeader(header).Should().BeFalse();
    }

    [Fact]
    public void IsValidAudioHeader_TooShort_ReturnsFalse()
    {
        var header = new byte[] { 0xFF, 0xF1, 0x50 };
        AudioValidationFunction.IsValidAudioHeader(header).Should().BeFalse();
    }

    [Fact]
    public async Task RejectRecording_PreservesFromStatus()
    {
        var recording = CreateRecording(status: "pending_upload");
        _db.Recordings.Add(recording);
        await _db.SaveChangesAsync();

        SetupBlobProperties(11 * 1024 * 1024); // Over limit

        await _sut.ValidateAudio(CreateEventGridEvent(), _functionContext);

        var modRecord = await _db.ModerationRecords.FirstOrDefaultAsync(m => m.RecordingId == recording.Id);
        modRecord.Should().NotBeNull();
        modRecord!.FromStatus.Should().Be("pending_upload");
        modRecord.ToStatus.Should().Be("rejected");
    }
}
