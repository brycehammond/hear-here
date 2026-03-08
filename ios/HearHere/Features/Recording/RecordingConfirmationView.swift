import MapKit
import SwiftUI

/// Upload state machine for tracking the multi-step upload flow.
enum UploadState: Equatable {
    case ready
    case creatingRecording
    case uploading(progress: Double)
    case completing
    case success(recordingId: UUID)
    case failed(String)

    static func == (lhs: UploadState, rhs: UploadState) -> Bool {
        switch (lhs, rhs) {
        case (.ready, .ready), (.creatingRecording, .creatingRecording), (.completing, .completing):
            return true
        case (.uploading(let a), .uploading(let b)):
            return a == b
        case (.success(let a), .success(let b)):
            return a == b
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

/// Summary card and upload flow for submitting a recorded audio file.
///
/// Displays the recording summary (subject, description, location, duration),
/// then executes the three-step upload: POST recording metadata, upload .m4a
/// to pre-signed URL, then POST upload-complete.
struct RecordingConfirmationView: View {
    @Bindable var viewModel: RecordingViewModel
    @Bindable var coordinator: RecordingCoordinator
    @State private var uploadState: UploadState = .ready
    @Environment(APIClient.self) private var apiClient: APIClient
    @Environment(UploadManager.self) private var uploadManager: UploadManager

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                summaryCard
                uploadSection
            }
            .padding()
        }
        .navigationTitle("Confirm")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationBarBackButtonHidden(uploadState != .ready)
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(viewModel.subject)
                .font(.title3)
                .fontWeight(.semibold)
                .accessibilityLabel("Subject: \(viewModel.subject)")

            if !viewModel.descriptionText.isEmpty {
                Text(viewModel.descriptionText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .accessibilityLabel("Description: \(viewModel.descriptionText)")
            }

            if let coordinate = viewModel.selectedCoordinate {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                ))) {
                    Marker("Location", coordinate: coordinate)
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .allowsHitTesting(false)
                .accessibilityLabel("Map showing recording location")
            }

            HStack {
                Label(viewModel.formattedElapsedTime, systemImage: "waveform")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Duration: \(viewModel.formattedElapsedTime)")
            }
        }
        .padding()
        .background(Theme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Upload Section

    @ViewBuilder
    private var uploadSection: some View {
        switch uploadState {
        case .ready:
            Button {
                Task {
                    await startUpload()
                }
            } label: {
                Label("Upload", systemImage: "arrow.up.circle.fill")
                    .font(.body)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Upload recording")
            .accessibilityHint("Begins uploading your recording for review")

        case .creatingRecording:
            progressView(label: "Preparing upload...")

        case .uploading(let progress):
            VStack(spacing: 12) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Upload progress: \(Int(progress * 100)) percent")

                Text("Uploading... \(Int(progress * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()

        case .completing:
            progressView(label: "Finalizing...")

        case .success:
            successView

        case .failed(let message):
            failureView(message: message)
        }
    }

    private func progressView(label: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .accessibilityLabel(label)
    }

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("Your recording is being reviewed!")
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text("This usually takes less than an hour. You'll see the status update in your profile.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                viewModel.resetForNewRecording()
                coordinator.popToRoot()
            } label: {
                Text("Done")
                    .font(.body)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Done")
            .accessibilityHint("Returns to the recording screen")
        }
        .padding()
    }

    private func failureView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("Upload Failed")
                .font(.title3)
                .fontWeight(.semibold)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await startUpload()
                }
            } label: {
                Label("Retry Upload", systemImage: "arrow.clockwise")
                    .font(.body)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Retry upload")
            .accessibilityHint("Attempts to upload the recording again")
        }
        .padding()
    }

    // MARK: - Upload Flow

    private func startUpload() async {
        guard let fileURL = viewModel.recordedFileURL,
              let coordinate = viewModel.selectedCoordinate else {
            uploadState = .failed("Missing recording data. Please try again.")
            return
        }

        uploadState = .creatingRecording

        do {
            // Step 1: Create recording on server
            let createRequest = CreateRecordingRequest(
                subject: viewModel.subject,
                description: viewModel.descriptionText.isEmpty ? nil : viewModel.descriptionText,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                durationSec: viewModel.elapsedTime
            )

            let createResponse = try await apiClient.request(
                .createRecording(createRequest),
                type: RecordingCreateResponse.self
            )

            guard let presignedURL = URL(string: createResponse.uploadUrl) else {
                uploadState = .failed("Invalid upload URL received from server.")
                return
            }

            // Step 2: Upload audio file
            uploadState = .uploading(progress: 0)
            let uploadTask = uploadManager.upload(
                fileURL: fileURL,
                to: presignedURL,
                recordingId: createResponse.id
            )

            // Poll upload progress
            while true {
                try await Task.sleep(for: .milliseconds(200))

                if let task = uploadManager.tasks.first(where: { $0.id == uploadTask.id }) {
                    switch task.state {
                    case .uploading(let progress):
                        uploadState = .uploading(progress: progress)
                    case .completed:
                        break
                    case .failed(let error):
                        uploadState = .failed(error.localizedDescription)
                        return
                    case .pending:
                        continue
                    }

                    if task.isCompleted {
                        break
                    }
                }
            }

            // Step 3: Notify server upload is complete
            uploadState = .completing
            try await apiClient.requestVoid(.uploadComplete(recordingId: createResponse.id))
            uploadState = .success(recordingId: createResponse.id)

        } catch {
            uploadState = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Previews

#Preview("Ready") {
    NavigationStack {
        RecordingConfirmationView(
            viewModel: {
                let vm = RecordingViewModel(
                    audioRecorder: PreviewConfirmRecorder(),
                    locationService: PreviewConfirmLocationService()
                )
                vm.subject = "Sunset at Golden Gate Bridge"
                vm.descriptionText = "The most beautiful sunset I've seen in years."
                vm.selectedCoordinate = CLLocationCoordinate2D(latitude: 37.8199, longitude: -122.4783)
                vm.elapsedTime = 134
                vm.recordedFileURL = URL(fileURLWithPath: "/tmp/recording.m4a")
                return vm
            }(),
            coordinator: RecordingCoordinator()
        )
    }
    .environment(APIClient.preview)
    .environment(UploadManager())
}

#Preview("Uploading") {
    NavigationStack {
        RecordingConfirmationView(
            viewModel: {
                let vm = RecordingViewModel(
                    audioRecorder: PreviewConfirmRecorder(),
                    locationService: PreviewConfirmLocationService()
                )
                vm.subject = "Morning birds in the park"
                vm.selectedCoordinate = CLLocationCoordinate2D(latitude: 37.77, longitude: -122.42)
                vm.elapsedTime = 60
                return vm
            }(),
            coordinator: RecordingCoordinator()
        )
    }
    .environment(APIClient.preview)
    .environment(UploadManager())
}

private final class PreviewConfirmRecorder: AudioRecorderProtocol, @unchecked Sendable {
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

private final class PreviewConfirmLocationService: LocationServiceProtocol, @unchecked Sendable {
    var currentLocation: CLLocation? = CLLocation(latitude: 37.7749, longitude: -122.4194)
    var permission: LocationPermission = .authorizedWhenInUse
    func requestWhenInUseAuthorization() {}
    func startUpdating(accuracy: LocationAccuracy) {}
    func stopUpdating() {}
}
