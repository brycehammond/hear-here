import AVFoundation
import MapKit
import SwiftUI

/// Form for entering recording metadata: subject, description, location, and audio preview.
///
/// Shows a character counter for the subject field, a small map preview with the
/// recording's pin location, and buttons to adjust the location, re-record, or submit.
struct RecordingMetadataView: View {
    @Bindable var viewModel: RecordingViewModel
    @Bindable var coordinator: RecordingCoordinator
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field {
        case subject
        case description
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                subjectSection
                descriptionSection
                locationSection
                audioPreviewSection
                actionButtons
            }
            .padding()
        }
        .navigationTitle("Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $coordinator.showLocationPicker) {
            LocationPickerView(
                selectedCoordinate: $viewModel.selectedCoordinate,
                onConfirm: {
                    coordinator.dismissLocationPicker()
                }
            )
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
                .accessibilityLabel("Dismiss keyboard")
            }
        }
    }

    // MARK: - Subject

    private var subjectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subject")
                .font(.headline)

            TextField("What is this recording about?", text: $viewModel.subject)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .subject)
                .onChange(of: viewModel.subject) { _, newValue in
                    if newValue.count > 200 {
                        viewModel.subject = String(newValue.prefix(200))
                    }
                }
                .accessibilityLabel("Recording subject")
                .accessibilityHint("Required. Maximum 200 characters.")

            HStack {
                if !viewModel.isSubjectValid && !viewModel.subject.isEmpty {
                    Text("Subject is required")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                Text("\(viewModel.subjectCharacterCount)/200")
                    .font(.caption)
                    .foregroundStyle(viewModel.subjectCharacterCount > 180 ? .orange : .secondary)
            }
        }
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)

            TextEditor(text: $viewModel.descriptionText)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(8)
                #if os(iOS)
                .background(Color(UIColor.systemGray6))
                #else
                .background(Color.gray.opacity(0.15))
                #endif
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .focused($focusedField, equals: .description)
                .onChange(of: viewModel.descriptionText) { _, newValue in
                    if newValue.count > 2000 {
                        viewModel.descriptionText = String(newValue.prefix(2000))
                    }
                }
                .accessibilityLabel("Recording description")
                .accessibilityHint("Optional. Maximum 2000 characters.")

            HStack {
                Text("Optional")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.descriptionText.count)/2000")
                    .font(.caption)
                    .foregroundStyle(viewModel.descriptionText.count > 1800 ? .orange : .secondary)
            }
        }
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location")
                .font(.headline)

            if let coordinate = viewModel.selectedCoordinate {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                ))) {
                    Marker("Recording Location", coordinate: coordinate)
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
                .accessibilityLabel("Map showing recording location")
            } else {
                RoundedRectangle(cornerRadius: 12)
                    #if os(iOS)
                    .fill(Color(UIColor.systemGray5))
                    #else
                    .fill(Color.gray.opacity(0.2))
                    #endif
                    .frame(height: 160)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "map")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text("No location selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("No location selected")
            }

            Button {
                coordinator.presentLocationPicker()
            } label: {
                Label("Adjust Location", systemImage: "mappin.and.ellipse")
                    .font(.body)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Adjust location")
            .accessibilityHint("Opens a map to choose a different pin location")
        }
    }

    // MARK: - Audio Preview

    private var audioPreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio Preview")
                .font(.headline)

            if let fileURL = viewModel.recordedFileURL {
                AudioPreviewPlayer(fileURL: fileURL)

                MetadataWaveformView(fileURL: fileURL)
                    .frame(height: 60)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                coordinator.showConfirmation()
            } label: {
                Text("Submit")
                    .font(.body)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.isMetadataValid)
            .accessibilityLabel("Submit recording")
            .accessibilityHint("Proceeds to the upload confirmation screen")

            Button(role: .destructive) {
                viewModel.reRecord()
                dismiss()
            } label: {
                Text("Re-record")
                    .font(.body)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Re-record")
            .accessibilityHint("Discards this recording and starts over")
        }
    }
}

// MARK: - Metadata Waveform View

/// Loads and displays a PCM waveform asynchronously for the metadata audio preview.
private struct MetadataWaveformView: View {
    let fileURL: URL
    @State private var peaks: [Float] = []
    @State private var duration: TimeInterval = 0
    @State private var currentTime: TimeInterval = 0
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading waveform")
            } else if peaks.isEmpty {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.waveformBackground)
                    .overlay {
                        Text("No waveform data")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            } else {
                PCMWaveformView(
                    peaks: peaks,
                    duration: duration,
                    currentTime: $currentTime,
                    selectionRange: .constant(nil)
                )
                .accessibilityLabel("Audio waveform preview, \(Int(duration)) seconds")
            }
        }
        .background(Theme.waveformBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task {
            await loadWaveform()
        }
    }

    private func loadWaveform() async {
        let provider = WaveformDataProvider()
        do {
            let data = try await provider.extractWaveform(from: fileURL, targetBinCount: 200)
            peaks = data.peaks
            let asset = AVAsset(url: fileURL)
            if let dur = try? await asset.load(.duration) {
                duration = CMTimeGetSeconds(dur)
            }
        } catch {
            // Graceful fallback: show empty state
        }
        isLoading = false
    }
}

// MARK: - Audio Preview Player

/// A simple inline audio player for previewing a recorded file.
private struct AudioPreviewPlayer: View {
    let fileURL: URL
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(isPlaying ? "Pause preview" : "Play preview")
            .accessibilityHint("Plays back the recorded audio")

            VStack(alignment: .leading) {
                Text("Recorded audio")
                    .font(.subheadline)
                Text(fileURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding()
        #if os(iOS)
        .background(Color(UIColor.systemGray6))
        #else
        .background(Color.gray.opacity(0.15))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Previews

#Preview("Filled") {
    NavigationStack {
        RecordingMetadataView(
            viewModel: {
                let vm = RecordingViewModel(
                    audioRecorder: PreviewMetadataRecorder(),
                    locationService: PreviewMetadataLocationService()
                )
                vm.subject = "A beautiful sunset at the bridge"
                vm.descriptionText = "The colors were incredible today."
                vm.selectedCoordinate = CLLocationCoordinate2D(latitude: 37.8199, longitude: -122.4783)
                vm.recordedFileURL = URL(fileURLWithPath: "/tmp/recording.m4a")
                return vm
            }(),
            coordinator: RecordingCoordinator()
        )
    }
}

#Preview("Empty") {
    NavigationStack {
        RecordingMetadataView(
            viewModel: {
                let vm = RecordingViewModel(
                    audioRecorder: PreviewMetadataRecorder(),
                    locationService: PreviewMetadataLocationService()
                )
                return vm
            }(),
            coordinator: RecordingCoordinator()
        )
    }
}

private final class PreviewMetadataRecorder: AudioRecorderProtocol, @unchecked Sendable {
    var state: RecordingState = .idle
    var currentTime: TimeInterval = 0
    var remainingTime: TimeInterval = 300
    var waveformSamples: [Float] = []
    var currentPeakPower: Float = -160
    func startRecording() throws {}
    func stopRecording() {}
    func pauseRecording() {}
    func resumeRecording() {}
    func cancelRecording() {}
}

private final class PreviewMetadataLocationService: LocationServiceProtocol, @unchecked Sendable {
    var currentLocation: CLLocation? = CLLocation(latitude: 37.7749, longitude: -122.4194)
    var permission: LocationPermission = .authorizedWhenInUse
    func requestWhenInUseAuthorization() {}
    func startUpdating(accuracy: LocationAccuracy) {}
    func stopUpdating() {}
}
