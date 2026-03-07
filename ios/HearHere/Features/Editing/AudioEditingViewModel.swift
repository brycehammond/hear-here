import AVFoundation
import Foundation
import Observation

/// State of the audio editing flow.
enum EditingState: Equatable {
    case idle
    case previewing
    case processing
    case completed(URL)
}

/// Manages audio editing state, waveform data, preview playback, and edit operations.
///
/// Coordinates between ``AudioEditSession`` for undo/redo operations,
/// ``WaveformDataProviding`` for waveform extraction, and
/// ``AudioEngineProtocol`` for exporting the final edited audio.
@Observable
@MainActor
final class AudioEditingViewModel {
    // MARK: - State

    var state: EditingState = .idle
    var waveformData: WaveformData?
    var currentTime: TimeInterval = 0
    var selectionRange: ClosedRange<TimeInterval>?
    var error: Error?

    private(set) var editSession: AudioEditSession

    var canUndo: Bool { editSession.canUndo }
    var canRedo: Bool { editSession.canRedo }
    var canTrimOrCut: Bool { selectionRange != nil }

    var duration: TimeInterval {
        editSession.effectiveDuration
    }

    var formattedCurrentTime: String {
        Self.formatTime(currentTime)
    }

    var formattedDuration: String {
        Self.formatTime(duration)
    }

    // MARK: - Dependencies

    private let fileURL: URL
    private let waveformProvider: any WaveformDataProviding
    private let audioEngine: any AudioEngineProtocol

    @ObservationIgnored
    private var player: AVPlayer?
    @ObservationIgnored
    private var timeObserver: Any?
    @ObservationIgnored
    private var lastReportedTime: TimeInterval = 0
    #if os(iOS)
    @ObservationIgnored
    private var displayLink: DisplayLinkProxy?
    #endif

    init(
        fileURL: URL,
        originalDuration: TimeInterval,
        waveformProvider: any WaveformDataProviding,
        audioEngine: any AudioEngineProtocol
    ) {
        self.fileURL = fileURL
        self.editSession = AudioEditSession(fileURL: fileURL, originalDuration: originalDuration)
        self.waveformProvider = waveformProvider
        self.audioEngine = audioEngine
    }

    // MARK: - Waveform

    func loadWaveform() async {
        do {
            waveformData = try await waveformProvider.extractWaveform(
                from: fileURL,
                targetBinCount: 2000
            )
        } catch {
            self.error = error
        }
    }

    // MARK: - Playback

    func play() {
        if player == nil {
            let playerItem = AVPlayerItem(url: fileURL)
            player = AVPlayer(playerItem: playerItem)
            setupTimeObserver()
        }
        player?.play()
        state = .previewing
        startDisplayLink()
    }

    func pause() {
        player?.pause()
        state = .idle
        stopDisplayLink()
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
        currentTime = time
    }

    func skipForward(seconds: TimeInterval = 5) {
        let target = min(currentTime + seconds, duration)
        seek(to: target)
    }

    func skipBackward(seconds: TimeInterval = 5) {
        let target = max(currentTime - seconds, 0)
        seek(to: target)
    }

    func cleanup() {
        cleanupPlaybackObservers()
    }

    // MARK: - Edit Operations

    func applyTrim() {
        guard let range = selectionRange else { return }
        editSession.apply(EditOperation.trim(start: range.lowerBound, end: range.upperBound))
        selectionRange = nil
    }

    func applyCut() {
        guard let range = selectionRange else { return }
        editSession.apply(EditOperation.cut(start: range.lowerBound, end: range.upperBound))
        selectionRange = nil
    }

    func applyFadeIn(duration: TimeInterval = 0.5) {
        editSession.apply(EditOperation.fadeIn(duration: duration))
    }

    func applyFadeOut(duration: TimeInterval = 0.5) {
        editSession.apply(EditOperation.fadeOut(duration: duration))
    }

    func applyNormalize(targetPeakDb: Float = -1.0) {
        editSession.apply(EditOperation.normalize(targetPeakDb: targetPeakDb))
    }

    func undo() {
        editSession.undo()
    }

    func redo() {
        editSession.redo()
    }

    // MARK: - Export

    func exportEdited() async -> URL {
        state = .processing
        do {
            let outputURL = try await audioEngine.process(
                inputURL: fileURL,
                operations: editSession.operations
            )
            state = .completed(outputURL)
            return outputURL
        } catch {
            self.error = error
            state = .idle
            return fileURL
        }
    }

    func skip() -> URL {
        fileURL
    }

    // MARK: - Private Playback

    private func setupTimeObserver() {
        guard let player else { return }
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.lastReportedTime = CMTimeGetSeconds(time)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pause()
                self?.currentTime = self?.duration ?? 0
            }
        }
    }

    private func startDisplayLink() {
        #if os(iOS)
        displayLink = DisplayLinkProxy { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = self.lastReportedTime
            }
        }
        #endif
    }

    private func stopDisplayLink() {
        #if os(iOS)
        displayLink?.stop()
        displayLink = nil
        #endif
    }

    private nonisolated func cleanupPlaybackObservers() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let timeObserver = self.timeObserver, let player = self.player {
                player.removeTimeObserver(timeObserver)
            }
            self.timeObserver = nil
            self.player?.pause()
            self.player = nil
            self.stopDisplayLink()
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        }
    }

    deinit {
        cleanupPlaybackObservers()
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - DisplayLinkProxy

#if os(iOS)
import UIKit

/// Wraps CADisplayLink for smooth playhead animation at display refresh rate.
final class DisplayLinkProxy: @unchecked Sendable {
    private var displayLink: CADisplayLink?
    private let callback: @Sendable () -> Void

    init(callback: @escaping @Sendable () -> Void) {
        self.callback = callback
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        callback()
    }

    deinit {
        stop()
    }
}
#endif
