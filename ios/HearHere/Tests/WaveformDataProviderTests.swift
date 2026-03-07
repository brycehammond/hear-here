import AVFoundation
import XCTest
@testable import HearHere

final class WaveformDataProviderTests: XCTestCase {
    /// Creates a synthetic mono audio file with a sine wave for testing.
    private func createTestAudioFile(
        duration: TimeInterval = 1.0,
        sampleRate: Double = 44100,
        frequency: Double = 440
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("waveform_test_\(UUID().uuidString).wav")

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            data[i] = Float(sin(2.0 * Double.pi * frequency * Double(i) / sampleRate))
        }

        try file.write(from: buffer)
        return url
    }

    func testExtractionProducesNonEmptyData() async throws {
        let url = try createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = WaveformDataProvider()
        let waveform = try await provider.extractWaveform(from: url, targetBinCount: 100)

        XCTAssertFalse(waveform.peaks.isEmpty)
    }

    func testBinCountMatchesRequested() async throws {
        let url = try createTestAudioFile(duration: 2.0)
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = WaveformDataProvider()
        let waveform = try await provider.extractWaveform(from: url, targetBinCount: 50)

        XCTAssertEqual(waveform.peaks.count, 50)
    }

    func testAllValuesAreNonNegative() async throws {
        let url = try createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = WaveformDataProvider()
        let waveform = try await provider.extractWaveform(from: url, targetBinCount: 100)

        for peak in waveform.peaks {
            XCTAssertGreaterThanOrEqual(peak, 0, "Peak value \(peak) should be non-negative")
        }
    }

    func testInvalidFileThrowsError() async {
        let bogusURL = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).wav")
        let provider = WaveformDataProvider()

        do {
            _ = try await provider.extractWaveform(from: bogusURL, targetBinCount: 100)
            XCTFail("Expected WaveformError to be thrown")
        } catch is WaveformError {
            // Expected
        } catch {
            XCTFail("Expected WaveformError, got \(error)")
        }
    }

    func testShortFileProducesFewerBins() async throws {
        let url = try createTestAudioFile(duration: 0.01)
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = WaveformDataProvider()
        let waveform = try await provider.extractWaveform(from: url, targetBinCount: 10000)

        XCTAssertLessThanOrEqual(waveform.peaks.count, 10000)
        XCTAssertFalse(waveform.peaks.isEmpty)
    }
}
