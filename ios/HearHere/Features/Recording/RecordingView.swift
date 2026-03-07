import AVFoundation
import CoreLocation
import SwiftUI

/// The main recording screen with a large record button, live timer, and waveform visualization.
///
/// Gates on microphone permission — if denied, shows a ``PermissionPromptView``
/// explaining why access is needed with a link to Settings.
struct RecordingView: View {
    @Bindable var viewModel: RecordingViewModel
    @Bindable var coordinator: RecordingCoordinator

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            ZStack {
                Theme.surface
                    .ignoresSafeArea()

                switch viewModel.phase {
                case .permissionNeeded:
                    microphonePermissionView
                case .idle:
                    idleView
                case .recording, .paused:
                    recordingActiveView
                case .recorded(let url):
                    Color.clear
                        .onAppear {
                            viewModel.phase = .editing(url)
                            coordinator.showEditing()
                        }
                case .editing:
                    Color.clear
                }

                if let countdown = viewModel.countdownRemaining {
                    countdownOverlay(count: countdown)
                }
            }
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: RecordingCoordinator.Destination.self) { destination in
                switch destination {
                case .editing:
                    editingDestinationView
                case .metadata:
                    RecordingMetadataView(viewModel: viewModel, coordinator: coordinator)
                case .confirmation:
                    RecordingConfirmationView(viewModel: viewModel, coordinator: coordinator)
                }
            }
            .onAppear {
                viewModel.checkPermissions()
            }
        }
    }

    // MARK: - Editing Destination

    private var editingDestinationView: some View {
        let fileURL = viewModel.recordedFileURL ?? URL(fileURLWithPath: "/dev/null")
        let duration = viewModel.elapsedTime

        let editVM = AudioEditingViewModel(
            fileURL: fileURL,
            originalDuration: duration,
            waveformProvider: WaveformDataProvider(),
            audioEngine: AudioEngine()
        )

        return AudioEditingView(
            viewModel: editVM,
            onComplete: { editedURL in
                viewModel.recordedFileURL = editedURL
                coordinator.showMetadata()
            },
            onCancel: {
                viewModel.reRecord()
                coordinator.popToRoot()
            }
        )
    }

    // MARK: - Idle State

    private var idleView: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("Tap to Record")
                .font(.title2)
                .foregroundStyle(.secondary)

            recordButton(isRecording: false)

            Text("Up to 5 minutes")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Recording Active State

    private var recordingActiveView: some View {
        VStack(spacing: 24) {
            Spacer()

            if viewModel.phase == .paused {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse)
                    .accessibilityLabel("Recording paused")

                Text("Paused")
                    .font(.headline)
                    .foregroundStyle(.orange)
            }

            if viewModel.isInCountdown {
                Text(viewModel.formattedRemainingTime)
                    .font(.system(.largeTitle, design: .monospaced))
                    .foregroundStyle(.red)
                    .accessibilityLabel("Time remaining: \(viewModel.formattedRemainingTime)")

                Text("Recording ending soon")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text(viewModel.formattedElapsedTime)
                    .font(.system(.largeTitle, design: .monospaced))
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Elapsed time: \(viewModel.formattedElapsedTime)")
            }

            AudioWaveformView(samples: viewModel.waveformSamples)
                .frame(height: 60)
                .padding(.horizontal)
                .accessibilityLabel("Audio waveform visualization")

            InputLevelMeter(
                level: viewModel.normalizedPeakLevel,
                isClipping: viewModel.isPeakClipping
            )
            .padding(.horizontal)

            HStack(spacing: 32) {
                // Pause / Resume button
                Button {
                    if viewModel.phase == .paused {
                        viewModel.resumeRecording()
                    } else {
                        viewModel.pauseRecording()
                    }
                } label: {
                    Image(systemName: viewModel.phase == .paused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(viewModel.phase == .paused ? .green : .orange)
                }
                .accessibilityLabel(viewModel.phase == .paused ? "Resume recording" : "Pause recording")
                .frame(minWidth: 44, minHeight: 44)

                // Stop button
                recordButton(isRecording: true)
            }

            Button(role: .cancel) {
                viewModel.cancelRecording()
            } label: {
                Text("Cancel")
                    .font(.body)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Cancel recording")
            .accessibilityHint("Discards the current recording")

            Spacer()
        }
        .padding()
    }

    // MARK: - Record Button

    private func recordButton(isRecording: Bool) -> some View {
        Button {
            if isRecording {
                viewModel.stopRecording()
            } else {
                viewModel.startRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 80, height: 80)

                if isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .frame(width: 28, height: 28)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 28, height: 28)
                }
            }
        }
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .accessibilityHint(isRecording ? "Stops the current recording" : "Begins recording audio")
        .frame(minWidth: 80, minHeight: 80)
    }

    // MARK: - Countdown Overlay

    private func countdownOverlay(count: Int) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            Text("\(count)")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.easeInOut, value: count)
        }
        .accessibilityLabel("Recording starts in \(count)")
    }

    // MARK: - Microphone Permission

    private var microphonePermissionView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "mic.slash.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Microphone Access Required")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text("Hear Here needs microphone access to record your stories. Your audio is only used for recordings you choose to share.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                Task {
                    await viewModel.requestMicrophonePermission()
                }
            } label: {
                Text("Enable Microphone")
                    .font(.body)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .accessibilityLabel("Enable microphone access")
            .accessibilityHint("Opens microphone permission request")

            Button {
                #if canImport(UIKit)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                #endif
            } label: {
                Text("Open Settings")
                    .font(.body)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Open Settings")
            .accessibilityHint("Opens the app settings to enable microphone access")

            Spacer()
        }
        .padding()
    }
}

// MARK: - Previews

#Preview("Idle") {
    RecordingView(
        viewModel: {
            let vm = RecordingViewModel(
                audioRecorder: PreviewAudioRecorder(),
                locationService: PreviewLocationService()
            )
            vm.phase = .idle
            return vm
        }(),
        coordinator: RecordingCoordinator()
    )
}

#Preview("Recording") {
    RecordingView(
        viewModel: {
            let vm = RecordingViewModel(
                audioRecorder: PreviewAudioRecorder(
                    mockSamples: (0..<30).map { _ in Float.random(in: 0.1...0.9) }
                ),
                locationService: PreviewLocationService()
            )
            vm.phase = .recording
            vm.elapsedTime = 45.0
            return vm
        }(),
        coordinator: RecordingCoordinator()
    )
}

#Preview("Permission Needed") {
    RecordingView(
        viewModel: {
            let vm = RecordingViewModel(
                audioRecorder: PreviewAudioRecorder(),
                locationService: PreviewLocationService()
            )
            vm.phase = .permissionNeeded
            return vm
        }(),
        coordinator: RecordingCoordinator()
    )
}

// MARK: - Preview Helpers

private final class PreviewAudioRecorder: AudioRecorderProtocol, @unchecked Sendable {
    var state: RecordingState = .idle
    var currentTime: TimeInterval = 0
    var remainingTime: TimeInterval = 300
    var waveformSamples: [Float]
    var currentPeakPower: Float = -30

    init(mockSamples: [Float] = []) {
        self.waveformSamples = mockSamples
    }

    func startRecording() throws {}
    func stopRecording() {}
    func pauseRecording() {}
    func resumeRecording() {}
    func cancelRecording() {}
}

private final class PreviewLocationService: LocationServiceProtocol, @unchecked Sendable {
    var currentLocation: CLLocation? = CLLocation(latitude: 37.7749, longitude: -122.4194)
    var permission: LocationPermission = .authorizedWhenInUse

    func requestWhenInUseAuthorization() {}
    func startUpdating(accuracy: LocationAccuracy) {}
    func stopUpdating() {}
}
