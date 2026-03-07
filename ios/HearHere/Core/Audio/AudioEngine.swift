import Accelerate
import AVFoundation
import Foundation

protocol AudioEngineProtocol: Sendable {
    func process(inputURL: URL, operations: [EditOperation]) async throws -> URL
}

enum AudioEngineError: Error, LocalizedError {
    case cannotReadFile
    case noAudioTrack
    case readFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .cannotReadFile: return "Cannot read the input audio file."
        case .noAudioTrack: return "No audio track found in the input file."
        case .readFailed: return "Failed to read audio samples from input."
        case .writeFailed: return "Failed to write the output audio file."
        }
    }
}

final class AudioEngine: AudioEngineProtocol {
    private let outputSampleRate: Double = 44100
    private let crossfadeDuration: TimeInterval = 0.005 // 5ms

    func process(inputURL: URL, operations: [EditOperation]) async throws -> URL {
        var samples = try await readPCMSamples(from: inputURL)

        for operation in operations {
            samples = applyOperation(operation, to: samples)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("processed_\(UUID().uuidString).m4a")

        try await writeAAC(samples: samples, to: outputURL)

        return outputURL
    }

    // MARK: - Read PCM

    private func readPCMSamples(from url: URL) async throws -> [Float] {
        let asset = AVAsset(url: url)

        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioEngineError.noAudioTrack
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw AudioEngineError.cannotReadFile
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: outputSampleRate,
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)

        guard reader.startReading() else {
            throw AudioEngineError.cannotReadFile
        }

        var allSamples: [Float] = []
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            _ = data.withUnsafeMutableBytes { rawBuffer in
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: rawBuffer.baseAddress!)
            }
            data.withUnsafeBytes { rawBuffer in
                let floats = rawBuffer.bindMemory(to: Float.self)
                allSamples.append(contentsOf: floats)
            }
        }

        guard reader.status == .completed else {
            throw AudioEngineError.readFailed
        }

        return allSamples
    }

    // MARK: - Apply Operations

    private func applyOperation(_ operation: EditOperation, to samples: [Float]) -> [Float] {
        switch operation {
        case .trim(let start, let end):
            return applyTrim(samples: samples, start: start, end: end)
        case .cut(let start, let end):
            return applyCut(samples: samples, start: start, end: end)
        case .fadeIn(let duration):
            return applyFadeIn(samples: samples, duration: duration)
        case .fadeOut(let duration):
            return applyFadeOut(samples: samples, duration: duration)
        case .normalize(let targetPeakDb):
            return applyNormalize(samples: samples, targetPeakDb: targetPeakDb)
        }
    }

    private func applyTrim(samples: [Float], start: TimeInterval, end: TimeInterval) -> [Float] {
        let startIndex = max(0, Int(start * outputSampleRate))
        let endIndex = min(samples.count, Int(end * outputSampleRate))
        guard startIndex < endIndex else { return [] }
        return Array(samples[startIndex..<endIndex])
    }

    private func applyCut(samples: [Float], start: TimeInterval, end: TimeInterval) -> [Float] {
        let cutStart = max(0, Int(start * outputSampleRate))
        let cutEnd = min(samples.count, Int(end * outputSampleRate))
        guard cutStart < cutEnd else { return samples }

        var result = Array(samples[0..<cutStart])
        let remaining = Array(samples[cutEnd..<samples.count])

        // Apply crossfade at splice point
        let crossfadeSamples = Int(crossfadeDuration * outputSampleRate)
        if crossfadeSamples > 0 && result.count >= crossfadeSamples && remaining.count >= crossfadeSamples {
            let fadeLen = crossfadeSamples

            // Fade out the end of the left segment
            for i in 0..<fadeLen {
                let factor = Float(fadeLen - 1 - i) / Float(fadeLen - 1)
                result[result.count - fadeLen + i] *= factor
            }

            // Fade in the start of the right segment and mix
            var rightFaded = remaining
            for i in 0..<fadeLen {
                let factor = Float(i) / Float(fadeLen - 1)
                rightFaded[i] *= factor
            }

            // Overlap-add the crossfade region
            for i in 0..<fadeLen {
                result[result.count - fadeLen + i] += rightFaded[i]
            }

            result.append(contentsOf: rightFaded[fadeLen...])
        } else {
            result.append(contentsOf: remaining)
        }

        return result
    }

    private func applyFadeIn(samples: [Float], duration: TimeInterval) -> [Float] {
        var result = samples
        let fadeLength = min(result.count, Int(duration * outputSampleRate))
        guard fadeLength > 0 else { return result }

        result.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            var rampStart: Float = 0
            var rampEnd: Float = 1
            // Generate linear ramp
            var ramp = [Float](repeating: 0, count: fadeLength)
            ramp.withUnsafeMutableBufferPointer { rampBuf in
                vDSP_vgen(&rampStart, &rampEnd, rampBuf.baseAddress!, 1, vDSP_Length(fadeLength))
            }
            // Multiply samples by ramp
            ramp.withUnsafeBufferPointer { rampBuf in
                vDSP_vmul(base, 1, rampBuf.baseAddress!, 1, base, 1, vDSP_Length(fadeLength))
            }
        }

        return result
    }

    private func applyFadeOut(samples: [Float], duration: TimeInterval) -> [Float] {
        var result = samples
        let fadeLength = min(result.count, Int(duration * outputSampleRate))
        guard fadeLength > 0 else { return result }

        let offset = result.count - fadeLength
        result.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            var rampStart: Float = 1
            var rampEnd: Float = 0
            var ramp = [Float](repeating: 0, count: fadeLength)
            ramp.withUnsafeMutableBufferPointer { rampBuf in
                vDSP_vgen(&rampStart, &rampEnd, rampBuf.baseAddress!, 1, vDSP_Length(fadeLength))
            }
            ramp.withUnsafeBufferPointer { rampBuf in
                vDSP_vmul(base + offset, 1, rampBuf.baseAddress!, 1, base + offset, 1, vDSP_Length(fadeLength))
            }
        }

        return result
    }

    private func applyNormalize(samples: [Float], targetPeakDb: Float) -> [Float] {
        guard !samples.isEmpty else { return samples }

        var result = samples
        var currentPeak: Float = 0
        vDSP_maxmgv(result, 1, &currentPeak, vDSP_Length(result.count))

        guard currentPeak > 0 else { return result }

        let targetLinear = pow(10.0, targetPeakDb / 20.0)
        var scale = targetLinear / currentPeak

        vDSP_vsmul(result, 1, &scale, &result, 1, vDSP_Length(result.count))

        return result
    }

    // MARK: - Write AAC

    private func writeAAC(samples: [Float], to outputURL: URL) async throws {
        let assetWriter: AVAssetWriter
        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        } catch {
            throw AudioEngineError.writeFailed
        }

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: outputSampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ]

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        writerInput.expectsMediaDataInRealTime = false

        assetWriter.add(writerInput)

        guard assetWriter.startWriting() else {
            throw AudioEngineError.writeFailed
        }
        assetWriter.startSession(atSourceTime: .zero)

        // Write samples in chunks
        let chunkSize = 8192
        let totalSamples = samples.count
        let sampleRate = outputSampleRate

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            nonisolated(unsafe) let writerInput = writerInput
            nonisolated(unsafe) let assetWriter = assetWriter
            nonisolated(unsafe) var offset = 0

            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio.write")) {
                while writerInput.isReadyForMoreMediaData {
                    if offset >= totalSamples {
                        writerInput.markAsFinished()
                        assetWriter.finishWriting {
                            if assetWriter.status == .completed {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: assetWriter.error ?? AudioEngineError.writeFailed)
                            }
                        }
                        return
                    }

                    let count = min(chunkSize, totalSamples - offset)
                    let chunk = Array(samples[offset..<offset + count])

                    if let sampleBuffer = Self.createSampleBuffer(
                        from: chunk,
                        offset: offset,
                        sampleRate: sampleRate
                    ) {
                        writerInput.append(sampleBuffer)
                    }

                    offset += count
                }
            }
        }
    }

    private static func createSampleBuffer(from samples: [Float], offset: Int, sampleRate: Double) -> CMSampleBuffer? {
        let frameCount = samples.count
        let bytesPerSample = MemoryLayout<Float>.size

        var blockBuffer: CMBlockBuffer?
        let dataSize = frameCount * bytesPerSample

        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard status == kCMBlockBufferNoErr, let block = blockBuffer else { return nil }

        status = CMBlockBufferReplaceDataBytes(
            with: samples,
            blockBuffer: block,
            offsetIntoDestination: 0,
            dataLength: dataSize
        )

        guard status == kCMBlockBufferNoErr else { return nil }

        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(bytesPerSample),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(bytesPerSample),
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        var formatDescription: CMAudioFormatDescription?
        status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )

        guard status == noErr, let format = formatDescription else { return nil }

        let presentationTime = CMTime(
            value: CMTimeValue(offset),
            timescale: CMTimeScale(sampleRate)
        )

        var sampleBuffer: CMSampleBuffer?
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: frameCount,
            presentationTimeStamp: presentationTime,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr else { return nil }
        return sampleBuffer
    }
}
