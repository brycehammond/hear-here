import AVFoundation
import CoreLocation
import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// State machine representing the recording flow phases.
enum RecordingPhase: Equatable {
    /// Ready to record, no recording in progress.
    case idle
    /// Microphone permission has not been granted.
    case permissionNeeded
    /// Actively recording audio.
    case recording
    /// Recording is paused.
    case paused
    /// Recording complete, audio file available at the URL.
    case recorded(URL)
    /// Audio is being edited before metadata entry.
    case editing(URL)

    static func == (lhs: RecordingPhase, rhs: RecordingPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.permissionNeeded, .permissionNeeded),
             (.recording, .recording), (.paused, .paused):
            return true
        case (.recorded(let a), .recorded(let b)):
            return a == b
        case (.editing(let a), .editing(let b)):
            return a == b
        default:
            return false
        }
    }
}

/// Manages the recording flow state, timer, and audio recorder interaction.
///
/// Drives ``RecordingView`` by exposing observable state for the current phase,
/// elapsed time, remaining time, waveform amplitude data, and countdown warnings.
@Observable
@MainActor
final class RecordingViewModel {
    // MARK: - State

    var phase: RecordingPhase = .idle
    var elapsedTime: TimeInterval = 0
    var error: Error?
    var countdownRemaining: Int?

    var remainingTime: TimeInterval {
        max(0, AudioRecorder.maxDuration - elapsedTime)
    }

    var isInCountdown: Bool {
        phase == .recording && remainingTime <= AudioRecorder.countdownWarningThreshold
    }

    var waveformSamples: [Float] {
        audioRecorder.waveformSamples
    }

    var normalizedPeakLevel: Float {
        InputLevelMeter.normalizeDecibels(audioRecorder.currentPeakPower)
    }

    var isPeakClipping: Bool {
        InputLevelMeter.isClipping(decibelLevel: audioRecorder.currentPeakPower)
    }

    var formattedElapsedTime: String {
        formatTime(elapsedTime)
    }

    var formattedRemainingTime: String {
        formatTime(remainingTime)
    }

    // MARK: - Metadata

    var subject: String = ""
    var descriptionText: String = ""
    var selectedCoordinate: CLLocationCoordinate2D?
    var recordedFileURL: URL?

    var subjectCharacterCount: Int { subject.count }
    var isSubjectValid: Bool { !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && subject.count <= 200 }
    var isMetadataValid: Bool { isSubjectValid }

    // MARK: - Dependencies

    private let audioRecorder: any AudioRecorderProtocol
    private let locationService: any LocationServiceProtocol
    private var timer: Timer?
    private var countdownTask: Task<Void, Never>?

    init(audioRecorder: any AudioRecorderProtocol, locationService: any LocationServiceProtocol) {
        self.audioRecorder = audioRecorder
        self.locationService = locationService
    }

    // MARK: - Actions

    func checkPermissions() {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch micStatus {
        case .authorized:
            phase = .idle
        case .notDetermined:
            phase = .permissionNeeded
        case .denied, .restricted:
            phase = .permissionNeeded
        @unknown default:
            phase = .permissionNeeded
        }
    }

    func requestMicrophonePermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        if granted {
            phase = .idle
        } else {
            phase = .permissionNeeded
        }
    }

    func startRecording() {
        error = nil
        countdownTask?.cancel()
        countdownTask = Task { @MainActor in
            for i in (1...3).reversed() {
                countdownRemaining = i
                triggerHaptic()
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { countdownRemaining = nil; return }
            }
            countdownRemaining = nil
            do {
                try audioRecorder.startRecording()
                phase = .recording
                elapsedTime = 0
                startTimer()
                locationService.startUpdating(accuracy: .bestForRecording)
                triggerHaptic()
            } catch {
                self.error = error
            }
        }
    }

    func stopRecording() {
        countdownTask?.cancel()
        countdownRemaining = nil
        audioRecorder.stopRecording()
        stopTimer()
        if case .finished(let url) = audioRecorder.state {
            recordedFileURL = url
            phase = .recorded(url)
            selectedCoordinate = locationService.currentLocation?.coordinate
        }
        locationService.stopUpdating()
        triggerHaptic()
    }

    func pauseRecording() {
        audioRecorder.pauseRecording()
        phase = .paused
        triggerHaptic()
    }

    func resumeRecording() {
        audioRecorder.resumeRecording()
        phase = .recording
        triggerHaptic()
    }

    func cancelRecording() {
        countdownTask?.cancel()
        countdownRemaining = nil
        audioRecorder.cancelRecording()
        stopTimer()
        elapsedTime = 0
        phase = .idle
    }

    func reRecord() {
        recordedFileURL = nil
        subject = ""
        descriptionText = ""
        selectedCoordinate = locationService.currentLocation?.coordinate
        phase = .idle
    }

    func resetForNewRecording() {
        recordedFileURL = nil
        subject = ""
        descriptionText = ""
        selectedCoordinate = nil
        error = nil
        elapsedTime = 0
        phase = .idle
    }

    // MARK: - Private

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTime()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateTime() {
        elapsedTime = audioRecorder.currentTime

        if case .finished(let url) = audioRecorder.state {
            stopTimer()
            recordedFileURL = url
            phase = .recorded(url)
            selectedCoordinate = locationService.currentLocation?.coordinate
            locationService.stopUpdating()
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(max(0, time))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func triggerHaptic() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }
}
