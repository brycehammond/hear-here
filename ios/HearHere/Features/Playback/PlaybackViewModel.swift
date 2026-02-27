import Foundation
import Observation

/// Reason options for reporting a recording that violates community guidelines.
enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case hateSpeech = "hate_speech"
    case harassment = "harassment"
    case violence = "violence"
    case sexualContent = "sexual_content"
    case spam = "spam"
    case misinformation = "misinformation"
    case other = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hateSpeech: return "Hate Speech"
        case .harassment: return "Harassment"
        case .violence: return "Violence"
        case .sexualContent: return "Sexual Content"
        case .spam: return "Spam"
        case .misinformation: return "Misinformation"
        case .other: return "Other"
        }
    }
}

/// Manages playback state for a single recording including audio controls,
/// loading/error states, and content reporting.
@Observable
@MainActor
final class PlaybackViewModel {
    // MARK: - State

    var recording: Recording
    var isLoadingPlayback = false
    var playbackError: Error?
    var showReportSheet = false
    var selectedReportReason: ReportReason?
    var isSubmittingReport = false
    var reportSubmitted = false
    var reportError: Error?

    // MARK: - Dependencies

    private let apiClient: APIClient
    private let audioPlayer: any AudioPlayerProtocol

    var playerState: PlaybackState {
        audioPlayer.state
    }

    var currentTime: TimeInterval {
        audioPlayer.currentTime
    }

    var duration: TimeInterval {
        audioPlayer.duration
    }

    var progress: Double {
        audioPlayer.progress
    }

    var formattedCurrentTime: String {
        formatTime(currentTime)
    }

    var formattedRemainingTime: String {
        let remaining = max(0, duration - currentTime)
        return "-\(formatTime(remaining))"
    }

    var isPlaying: Bool {
        if case .playing = playerState { return true }
        return false
    }

    init(recording: Recording, apiClient: APIClient, audioPlayer: any AudioPlayerProtocol) {
        self.recording = recording
        self.apiClient = apiClient
        self.audioPlayer = audioPlayer
    }

    // MARK: - Playback Actions

    func loadAndPlay() async {
        isLoadingPlayback = true
        playbackError = nil

        do {
            let response = try await apiClient.request(
                .playback(recordingId: recording.id),
                type: PlaybackResponse.self
            )

            guard let url = URL(string: response.playbackUrl) else {
                playbackError = APIError.unknown(URLError(.badURL))
                isLoadingPlayback = false
                return
            }

            audioPlayer.play(url: url)
            isLoadingPlayback = false
        } catch {
            playbackError = error
            isLoadingPlayback = false
        }
    }

    func togglePlayPause() {
        switch playerState {
        case .idle:
            Task {
                await loadAndPlay()
            }
        case .playing:
            audioPlayer.pause()
        case .paused:
            audioPlayer.resume()
        case .loading:
            break
        case .failed:
            Task {
                await loadAndPlay()
            }
        }
    }

    func seek(to time: TimeInterval) {
        Task {
            await audioPlayer.seek(to: time)
        }
    }

    func stop() {
        audioPlayer.stop()
    }

    // MARK: - Report Actions

    func submitReport() async {
        guard let reason = selectedReportReason else { return }
        isSubmittingReport = true
        reportError = nil

        do {
            let request = CreateReportRequest(
                recordingId: recording.id,
                reason: reason.rawValue
            )
            _ = try await apiClient.request(
                .createReport(request),
                type: ReportResponse.self
            )
            reportSubmitted = true
            isSubmittingReport = false
            showReportSheet = false
        } catch {
            reportError = error
            isSubmittingReport = false
        }
    }

    // MARK: - Private

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(max(0, seconds))
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
