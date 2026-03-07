import AVFoundation
import XCTest
@testable import HearHere

final class AudioEngineTests: XCTestCase {
    /// Creates a synthetic mono audio file with a sine wave for testing.
    private func createTestAudioFile(
        duration: TimeInterval = 2.0,
        sampleRate: Double = 44100,
        frequency: Double = 440,
        amplitude: Float = 0.8
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine_test_\(UUID().uuidString).wav")

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
            data[i] = amplitude * Float(sin(2.0 * Double.pi * frequency * Double(i) / sampleRate))
        }

        try file.write(from: buffer)
        return url
    }

    /// Reads PCM Float32 samples from a file for verification.
    private func readSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: file.processingFormat.sampleRate,
            channels: 1,
            interleaved: false
        )!
        let frameCount = AVAudioFrameCount(file.length)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    /// Gets the duration of an audio file.
    private func getDuration(of url: URL) async throws -> TimeInterval {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    func testTrimProducesCorrectShorterDuration() async throws {
        let inputURL = try createTestAudioFile(duration: 3.0)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let engine = AudioEngine()
        let outputURL = try await engine.process(
            inputURL: inputURL,
            operations: [.trim(start: 0.5, end: 2.5)]
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let outputDuration = try await getDuration(of: outputURL)
        XCTAssertEqual(outputDuration, 2.0, accuracy: 0.1, "Expected ~2.0s, got \(outputDuration)s")
    }

    func testCutRemovesRegion() async throws {
        let inputURL = try createTestAudioFile(duration: 3.0)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let engine = AudioEngine()
        let outputURL = try await engine.process(
            inputURL: inputURL,
            operations: [.cut(start: 1.0, end: 2.0)]
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let outputDuration = try await getDuration(of: outputURL)
        XCTAssertEqual(outputDuration, 2.0, accuracy: 0.1, "Expected ~2.0s, got \(outputDuration)s")
    }

    func testFadeInRampsAmplitudeFromZero() async throws {
        let inputURL = try createTestAudioFile(duration: 1.0, amplitude: 1.0)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let engine = AudioEngine()
        let outputURL = try await engine.process(
            inputURL: inputURL,
            operations: [.fadeIn(duration: 0.5)]
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let samples = try readSamples(from: outputURL)
        XCTAssertGreaterThan(samples.count, 100, "Output file has too few samples")

        let earlyRMS = sqrt(samples.prefix(50).map { $0 * $0 }.reduce(0, +) / 50)
        let midPoint = samples.count / 2
        let midRMS = sqrt(samples[midPoint..<min(midPoint + 50, samples.count)].map { $0 * $0 }.reduce(0, +) / 50)

        XCTAssertLessThan(earlyRMS, midRMS, "Early samples (RMS: \(earlyRMS)) should be quieter than mid samples (RMS: \(midRMS))")
    }

    func testFadeOutRampsAmplitudeToZero() async throws {
        let inputURL = try createTestAudioFile(duration: 1.0, amplitude: 1.0)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let engine = AudioEngine()
        let outputURL = try await engine.process(
            inputURL: inputURL,
            operations: [.fadeOut(duration: 0.5)]
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let samples = try readSamples(from: outputURL)
        XCTAssertGreaterThan(samples.count, 100, "Output file has too few samples")

        let lateRMS = sqrt(samples.suffix(50).map { $0 * $0 }.reduce(0, +) / 50)
        let midPoint = samples.count / 2
        let midRMS = sqrt(samples[midPoint..<min(midPoint + 50, samples.count)].map { $0 * $0 }.reduce(0, +) / 50)

        XCTAssertLessThan(lateRMS, midRMS, "Late samples (RMS: \(lateRMS)) should be quieter than mid samples (RMS: \(midRMS))")
    }

    func testNormalizeHitsTargetPeak() async throws {
        let inputURL = try createTestAudioFile(duration: 1.0, amplitude: 0.3)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let targetDb: Float = -1.0
        let engine = AudioEngine()
        let outputURL = try await engine.process(
            inputURL: inputURL,
            operations: [.normalize(targetPeakDb: targetDb)]
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let samples = try readSamples(from: outputURL)
        let peak = samples.map { abs($0) }.max() ?? 0

        let targetLinear = pow(10.0, targetDb / 20.0)
        XCTAssertEqual(peak, targetLinear, accuracy: 0.15, "Peak \(peak) should be near target \(targetLinear)")
    }

    func testExportProducesValidM4AFile() async throws {
        let inputURL = try createTestAudioFile(duration: 1.0)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let engine = AudioEngine()
        let outputURL = try await engine.process(
            inputURL: inputURL,
            operations: [.trim(start: 0.0, end: 1.0)]
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let data = try Data(contentsOf: outputURL)
        XCTAssertGreaterThan(data.count, 8, "Output file should have content")

        let ftypRange = 4..<8
        let ftypBytes = data.subdata(in: ftypRange)
        let ftypString = String(data: ftypBytes, encoding: .ascii)
        XCTAssertEqual(ftypString, "ftyp", "File should start with ftyp atom, got \(ftypString ?? "nil")")
    }

    func testOutputFileSizeIsReasonable() async throws {
        let inputURL = try createTestAudioFile(duration: 2.0)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let engine = AudioEngine()
        let outputURL = try await engine.process(
            inputURL: inputURL,
            operations: [.trim(start: 0.0, end: 2.0)]
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attrs[.size] as? Int ?? 0

        XCTAssertGreaterThan(fileSize, 1000, "File size \(fileSize) seems too small")
        XCTAssertLessThan(fileSize, 500_000, "File size \(fileSize) seems too large for 2s AAC")
    }
}
