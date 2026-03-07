import Accelerate
import AVFoundation
import Foundation

struct WaveformData: Sendable {
    let peaks: [Float]
    let sampleRate: Double
}

enum WaveformError: Error, LocalizedError {
    case cannotReadFile
    case noAudioTrack
    case readFailed

    var errorDescription: String? {
        switch self {
        case .cannotReadFile: return "Cannot read the audio file."
        case .noAudioTrack: return "No audio track found in the file."
        case .readFailed: return "Failed to read audio samples."
        }
    }
}

protocol WaveformDataProviding: Sendable {
    func extractWaveform(from url: URL, targetBinCount: Int) async throws -> WaveformData
}

final class WaveformDataProvider: WaveformDataProviding {
    func extractWaveform(from url: URL, targetBinCount: Int) async throws -> WaveformData {
        let asset = AVAsset(url: url)

        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw WaveformError.noAudioTrack
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw WaveformError.cannotReadFile
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100,
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)

        guard reader.startReading() else {
            throw WaveformError.cannotReadFile
        }

        // Collect all samples
        var allSamples: [Float] = []
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { rawBuffer in
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: rawBuffer.baseAddress!)
            }
            let floatCount = length / MemoryLayout<Float>.size
            data.withUnsafeBytes { rawBuffer in
                let floats = rawBuffer.bindMemory(to: Float.self)
                allSamples.append(contentsOf: floats)
            }
        }

        guard reader.status == .completed, !allSamples.isEmpty else {
            throw WaveformError.readFailed
        }

        // Downsample into bins using absolute values and max per bin
        let totalSamples = allSamples.count
        let binCount = min(targetBinCount, totalSamples)
        let samplesPerBin = totalSamples / binCount

        var peaks = [Float](repeating: 0, count: binCount)

        allSamples.withUnsafeBufferPointer { samplesPtr in
            guard let base = samplesPtr.baseAddress else { return }
            for bin in 0..<binCount {
                let start = bin * samplesPerBin
                let count = min(samplesPerBin, totalSamples - start)
                guard count > 0 else { continue }

                var maxVal: Float = 0
                vDSP_maxmgv(base + start, 1, &maxVal, vDSP_Length(count))
                peaks[bin] = maxVal
            }
        }

        return WaveformData(peaks: peaks, sampleRate: 44100)
    }
}
