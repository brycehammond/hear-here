import AVFoundation
import Foundation
import Observation

/// The current state of the audio recorder.
enum RecordingState: Sendable {
    /// The recorder is idle and ready to start a new recording.
    case idle

    /// The recorder is actively capturing audio.
    case recording

    /// The recorder has been paused.
    case paused

    /// The recording has finished and the file is available at the associated URL.
    case finished(URL)

    /// The recording failed with an error.
    case failed(Error)
}

/// Protocol for audio recording, enabling mock injection for testing.
protocol AudioRecorderProtocol: Sendable {
    /// The current recording state.
    var state: RecordingState { get }

    /// The elapsed recording time in seconds.
    var currentTime: TimeInterval { get }

    /// The remaining time before the maximum duration is reached, in seconds.
    var remainingTime: TimeInterval { get }

    /// Waveform amplitude samples collected during recording for visualization.
    /// Values are normalized to 0.0...1.0.
    var waveformSamples: [Float] { get }

    /// Starts recording audio to a new temporary file.
    /// - Throws: If the audio session or recorder cannot be configured.
    func startRecording() throws

    /// Stops the current recording and finalizes the audio file.
    func stopRecording()

    /// Discards the current recording and returns to the idle state.
    func cancelRecording()
}

/// Records audio using AVAudioRecorder with AAC encoding at 44.1kHz, 64kbps, mono.
///
/// Enforces a maximum recording duration of 5 minutes with a countdown
/// that begins at 4:30. Collects waveform amplitude data for real-time
/// visualization during recording.
///
/// ## Audio Format
/// - Codec: AAC (kAudioFormatMPEG4AAC)
/// - Sample Rate: 44,100 Hz
/// - Bit Rate: 64 kbps
/// - Channels: Mono
/// - Container: .m4a
/// - Max Duration: 5 minutes (~2.4 MB)
@Observable
final class AudioRecorder: NSObject, @unchecked Sendable, AudioRecorderProtocol {
    /// Maximum recording duration in seconds (5 minutes).
    static let maxDuration: TimeInterval = 300

    /// The time remaining when the countdown warning begins (30 seconds).
    static let countdownWarningThreshold: TimeInterval = 30

    private(set) var state: RecordingState = .idle
    private(set) var currentTime: TimeInterval = 0
    private(set) var waveformSamples: [Float] = []

    var remainingTime: TimeInterval {
        max(0, Self.maxDuration - currentTime)
    }

    /// Whether the recording is in the countdown warning zone (last 30 seconds).
    var isInCountdown: Bool {
        state.isRecording && remainingTime <= Self.countdownWarningThreshold
    }

    @ObservationIgnored
    private var recorder: AVAudioRecorder?
    @ObservationIgnored
    private var meteringTimer: Timer?
    @ObservationIgnored
    private let audioSession: AudioSessionManager

    /// Creates an audio recorder with the given audio session manager.
    /// - Parameter audioSession: The session manager for configuring AVAudioSession.
    init(audioSession: AudioSessionManager = AudioSessionManager()) {
        self.audioSession = audioSession
        super.init()
    }

    func startRecording() throws {
        try audioSession.configureForRecording()

        let fileURL = Self.newRecordingURL()
        let recorder = try AVAudioRecorder(url: fileURL, settings: Self.recordingSettings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true

        guard recorder.record(forDuration: Self.maxDuration) else {
            state = .failed(AudioRecorderError.failedToStart)
            return
        }

        self.recorder = recorder
        state = .recording
        currentTime = 0
        waveformSamples = []
        startMeteringTimer()
    }

    func stopRecording() {
        guard let recorder, recorder.isRecording else { return }
        stopMeteringTimer()
        recorder.stop()
        state = .finished(recorder.url)
    }

    func cancelRecording() {
        stopMeteringTimer()
        recorder?.stop()
        if let url = recorder?.url {
            try? FileManager.default.removeItem(at: url)
        }
        recorder = nil
        state = .idle
        currentTime = 0
        waveformSamples = []
    }

    // MARK: - Private

    private static nonisolated(unsafe) let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        AVEncoderBitRateKey: 64_000,
    ]

    private static func newRecordingURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
        let filename = "recording_\(UUID().uuidString).m4a"
        return directory.appendingPathComponent(filename)
    }

    private func startMeteringTimer() {
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateMetering()
        }
    }

    private func stopMeteringTimer() {
        meteringTimer?.invalidate()
        meteringTimer = nil
    }

    private func updateMetering() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        currentTime = recorder.currentTime

        // Normalize the average power from dB (-160...0) to 0.0...1.0
        let averagePower = recorder.averagePower(forChannel: 0)
        let normalizedPower = Self.normalizeDecibels(averagePower)
        waveformSamples.append(normalizedPower)

        // Auto-stop is handled by AVAudioRecorder's forDuration parameter,
        // which will call the delegate's audioRecorderDidFinishRecording.
    }

    /// Normalizes a decibel value from AVAudioRecorder's range (-160...0) to 0.0...1.0.
    private static func normalizeDecibels(_ decibels: Float) -> Float {
        let minDb: Float = -60
        let clamped = max(minDb, min(0, decibels))
        return (clamped - minDb) / (0 - minDb)
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        stopMeteringTimer()
        if flag {
            state = .finished(recorder.url)
        } else {
            state = .failed(AudioRecorderError.recordingFailed)
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        stopMeteringTimer()
        state = .failed(error ?? AudioRecorderError.encodingFailed)
    }
}

// MARK: - RecordingState Helpers

extension RecordingState {
    /// Whether the recorder is actively capturing audio.
    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }
}

// MARK: - AudioRecorderError

/// Errors specific to the audio recording process.
enum AudioRecorderError: Error, LocalizedError {
    case failedToStart
    case recordingFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .failedToStart:
            return "Could not start recording. Please check your microphone permissions."
        case .recordingFailed:
            return "The recording was interrupted or failed."
        case .encodingFailed:
            return "An error occurred while encoding the audio."
        }
    }
}
