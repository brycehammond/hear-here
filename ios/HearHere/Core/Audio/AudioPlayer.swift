import AVFoundation
import Foundation
import Observation

/// The current state of the audio player.
enum PlaybackState: Sendable {
    /// The player has no audio loaded.
    case idle

    /// The player is loading audio from a URL.
    case loading

    /// The player is actively playing audio.
    case playing

    /// The player is paused with audio loaded.
    case paused

    /// Playback failed with an error.
    case failed(Error)
}

/// Protocol for audio playback, enabling mock injection for testing.
protocol AudioPlayerProtocol: Sendable {
    /// The current playback state.
    var state: PlaybackState { get }

    /// The current playback position in seconds.
    var currentTime: TimeInterval { get }

    /// The total duration of the loaded audio in seconds.
    var duration: TimeInterval { get }

    /// The playback progress as a value from 0.0 to 1.0.
    var progress: Double { get }

    /// Loads and begins playing audio from the given URL.
    /// - Parameter url: A signed URL for streaming audio.
    func play(url: URL)

    /// Pauses playback at the current position.
    func pause()

    /// Resumes playback from the paused position.
    func resume()

    /// Seeks to a specific time position.
    /// - Parameter time: The target time in seconds.
    func seek(to time: TimeInterval) async

    /// Stops playback and unloads the audio.
    func stop()
}

/// Streams and plays audio from signed URLs using AVPlayer.
///
/// Observes the player's status and timing to expose reactive state for
/// the UI layer. Supports play, pause, seek, and progress observation.
/// Uses `AVPlayer` for HTTP progressive download, enabling playback
/// before the full file is downloaded.
@Observable
final class AudioPlayer: NSObject, @unchecked Sendable, AudioPlayerProtocol {
    private(set) var state: PlaybackState = .idle
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    /// A formatted string of the current playback time (e.g., "1:23").
    var formattedCurrentTime: String {
        Self.formatTime(currentTime)
    }

    /// A formatted string of the remaining playback time (e.g., "-2:10").
    var formattedRemainingTime: String {
        let remaining = max(0, duration - currentTime)
        return "-\(Self.formatTime(remaining))"
    }

    @ObservationIgnored
    private var player: AVPlayer?
    @ObservationIgnored
    private var timeObserver: Any?
    @ObservationIgnored
    private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored
    private var durationObservation: NSKeyValueObservation?
    @ObservationIgnored
    private let audioSession: AudioSessionManager

    /// Creates an audio player with the given audio session manager.
    /// - Parameter audioSession: The session manager for configuring AVAudioSession.
    init(audioSession: AudioSessionManager = AudioSessionManager()) {
        self.audioSession = audioSession
        super.init()
    }

    deinit {
        removeObservers()
    }

    func play(url: URL) {
        stop()

        do {
            try audioSession.configureForPlayback()
        } catch {
            state = .failed(error)
            return
        }

        state = .loading

        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        self.player = player

        observePlayerStatus(playerItem: playerItem)
        observePlaybackTime(player: player)

        player.play()
    }

    func pause() {
        player?.pause()
        state = .paused
    }

    func resume() {
        player?.play()
        state = .playing
    }

    func seek(to time: TimeInterval) async {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        await player?.seek(to: cmTime)
        currentTime = time
    }

    func stop() {
        removeObservers()
        player?.pause()
        player = nil
        state = .idle
        currentTime = 0
        duration = 0
    }

    // MARK: - Private

    private func observePlayerStatus(playerItem: AVPlayerItem) {
        statusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    self?.state = .playing
                    if let durationCMTime = self?.player?.currentItem?.duration,
                       durationCMTime.isNumeric {
                        self?.duration = CMTimeGetSeconds(durationCMTime)
                    }
                case .failed:
                    self?.state = .failed(item.error ?? URLError(.unknown))
                default:
                    break
                }
            }
        }

        durationObservation = playerItem.observe(\.duration, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                if item.duration.isNumeric {
                    self?.duration = CMTimeGetSeconds(item.duration)
                }
            }
        }
    }

    private func observePlaybackTime(player: AVPlayer) {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = CMTimeGetSeconds(time)
        }

        // Observe when playback reaches the end
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.state = .paused
            self?.currentTime = self?.duration ?? 0
        }
    }

    private func removeObservers() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
        durationObservation?.invalidate()
        durationObservation = nil
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(max(0, seconds))
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
