import Foundation
import Observation
import SwiftUI

/// Shared playback state that persists across tab navigation.
///
/// The mini player bar reads from this to display the currently playing recording.
/// It is injected via SwiftUI Environment so all tabs can observe it.
@Observable
@MainActor
final class SharedPlaybackState {
    var currentRecording: Recording?
    var isPlaying = false
    var progress: Double = 0
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0

    private let audioPlayer: any AudioPlayerProtocol

    var isVisible: Bool {
        currentRecording != nil
    }

    var formattedCurrentTime: String {
        formatTime(currentTime)
    }

    init(audioPlayer: any AudioPlayerProtocol) {
        self.audioPlayer = audioPlayer
    }

    func play(recording: Recording, url: URL) {
        currentRecording = recording
        audioPlayer.play(url: url)
        isPlaying = true
    }

    func togglePlayPause() {
        switch audioPlayer.state {
        case .playing:
            audioPlayer.pause()
            isPlaying = false
        case .paused:
            audioPlayer.resume()
            isPlaying = true
        default:
            break
        }
    }

    func stop() {
        audioPlayer.stop()
        currentRecording = nil
        isPlaying = false
        progress = 0
        currentTime = 0
        duration = 0
    }

    func updateFromPlayer() {
        isPlaying = audioPlayer.state == .playing
        currentTime = audioPlayer.currentTime
        duration = audioPlayer.duration
        progress = audioPlayer.progress
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(max(0, seconds))
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Persistent mini-player bar shown at the bottom of the tab view when audio is playing.
///
/// Shows the current recording subject, a play/pause toggle, and a thin progress bar.
/// Tapping the bar expands to the full ``PlaybackView``.
struct MiniPlayerView: View {
    @Bindable var playbackState: SharedPlaybackState
    var onTap: () -> Void

    var body: some View {
        if playbackState.isVisible, let recording = playbackState.currentRecording {
            VStack(spacing: 0) {
                // Progress bar
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * playbackState.progress, height: 2)
                }
                .frame(height: 2)
                .accessibilityLabel("Playback progress: \(Int(playbackState.progress * 100)) percent")

                Button {
                    onTap()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recording.subject)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .foregroundStyle(.primary)

                            Text(playbackState.formattedCurrentTime)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Spacer()

                        Button {
                            playbackState.togglePlayPause()
                        } label: {
                            Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel(playbackState.isPlaying ? "Pause" : "Play")
                        .accessibilityHint(playbackState.isPlaying ? "Pauses the current recording" : "Resumes playback")
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(minHeight: 52)
                }
                .accessibilityLabel("Now playing: \(recording.subject)")
                .accessibilityHint("Tap to open full playback view")
            }
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Previews

#Preview("Playing") {
    VStack {
        Spacer()
        MiniPlayerView(
            playbackState: {
                let state = SharedPlaybackState(audioPlayer: PreviewMiniPlayer())
                state.currentRecording = .preview
                state.isPlaying = true
                state.progress = 0.35
                state.currentTime = 47
                state.duration = 134
                return state
            }(),
            onTap: {}
        )
    }
}

#Preview("Paused") {
    VStack {
        Spacer()
        MiniPlayerView(
            playbackState: {
                let state = SharedPlaybackState(audioPlayer: PreviewMiniPlayer())
                state.currentRecording = .preview
                state.isPlaying = false
                state.progress = 0.6
                state.currentTime = 80
                state.duration = 134
                return state
            }(),
            onTap: {}
        )
    }
}

#Preview("Hidden") {
    VStack {
        Spacer()
        MiniPlayerView(
            playbackState: SharedPlaybackState(audioPlayer: PreviewMiniPlayer()),
            onTap: {}
        )
    }
}

private final class PreviewMiniPlayer: AudioPlayerProtocol, @unchecked Sendable {
    var state: PlaybackState = .paused
    var currentTime: TimeInterval = 47
    var duration: TimeInterval = 134
    var progress: Double { duration > 0 ? currentTime / duration : 0 }
    func play(url: URL) {}
    func pause() {}
    func resume() {}
    func seek(to time: TimeInterval) async {}
    func stop() {}
}
