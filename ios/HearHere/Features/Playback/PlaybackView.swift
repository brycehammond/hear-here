import MapKit
import SwiftUI

/// Full playback screen showing recording details, map, audio controls, and report option.
struct PlaybackView: View {
    @Bindable var viewModel: PlaybackViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                mapSection
                audioControlsSection
            }
            .padding()
        }
        .navigationTitle("Playback")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        viewModel.showReportSheet = true
                    } label: {
                        Label("Report", systemImage: "flag")
                    }
                    .accessibilityLabel("Report this recording")

                    Button {
                        // Share placeholder for future implementation
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share this recording")
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("More options")
                }
            }
        }
        .sheet(isPresented: $viewModel.showReportSheet) {
            reportSheet
        }
        .alert("Report Submitted", isPresented: $viewModel.reportSubmitted) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Thank you for your report. We'll review this recording.")
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.recording.subject)
                .font(.title2)
                .fontWeight(.bold)
                .accessibilityLabel("Subject: \(viewModel.recording.subject)")

            if let description = viewModel.recording.description, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Description: \(description)")
            }

            Text(relativeTimeString(from: viewModel.recording.createdAt))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Recorded \(relativeTimeString(from: viewModel.recording.createdAt))")
        }
    }

    // MARK: - Map

    private var mapSection: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: viewModel.recording.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        ))) {
            Marker(viewModel.recording.subject, coordinate: viewModel.recording.coordinate)
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
        .accessibilityLabel("Map showing where this recording was made")
    }

    // MARK: - Audio Controls

    private var audioControlsSection: some View {
        VStack(spacing: 16) {
            if let error = viewModel.playbackError {
                errorView(error: error)
            }

            // Scrub bar
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { viewModel.progress },
                        set: { newValue in
                            let targetTime = newValue * viewModel.duration
                            viewModel.seek(to: targetTime)
                        }
                    ),
                    in: 0...1
                )
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(viewModel.formattedCurrentTime) of \(viewModel.formattedRemainingTime)")

                HStack {
                    Text(viewModel.formattedCurrentTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Text(viewModel.formattedRemainingTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // Play/Pause button
            HStack {
                Spacer()
                Button {
                    viewModel.togglePlayPause()
                } label: {
                    Group {
                        if viewModel.isLoadingPlayback {
                            ProgressView()
                                .frame(width: 56, height: 56)
                        } else {
                            Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.accentColor)
                        }
                    }
                    .frame(minWidth: 56, minHeight: 56)
                }
                .disabled(viewModel.isLoadingPlayback)
                .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
                .accessibilityHint(viewModel.isPlaying ? "Pauses audio playback" : "Plays the recording")
                Spacer()
            }
        }
        .padding()
        .background(Theme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func errorView(error: Error) -> some View {
        VStack(spacing: 8) {
            Text("Playback Error")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task {
                    await viewModel.loadAndPlay()
                }
            }
            .font(.caption)
            .frame(minHeight: 44)
            .accessibilityLabel("Retry playback")
        }
        .padding()
        .background(Color(.systemOrange).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Report Sheet

    private var reportSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ReportReason.allCases) { reason in
                        Button {
                            viewModel.selectedReportReason = reason
                        } label: {
                            HStack {
                                Text(reason.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if viewModel.selectedReportReason == reason {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.accentColor)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityLabel(reason.displayName)
                        .accessibilityAddTraits(viewModel.selectedReportReason == reason ? .isSelected : [])
                    }
                } header: {
                    Text("Select a reason")
                }

                if let error = viewModel.reportError {
                    Section {
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Report Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.showReportSheet = false
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Cancel report")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task {
                            await viewModel.submitReport()
                        }
                    }
                    .disabled(viewModel.selectedReportReason == nil || viewModel.isSubmittingReport)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Submit report")
                    .accessibilityHint("Reports this recording for review")
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func relativeTimeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Previews

#Preview("Populated") {
    NavigationStack {
        PlaybackView(
            viewModel: PlaybackViewModel(
                recording: .preview,
                apiClient: .preview,
                audioPlayer: PreviewPlaybackPlayer()
            )
        )
    }
}

#Preview("Loading") {
    NavigationStack {
        PlaybackView(
            viewModel: {
                let vm = PlaybackViewModel(
                    recording: .preview,
                    apiClient: .preview,
                    audioPlayer: PreviewPlaybackPlayer()
                )
                vm.isLoadingPlayback = true
                return vm
            }()
        )
    }
}

#Preview("Error") {
    NavigationStack {
        PlaybackView(
            viewModel: {
                let vm = PlaybackViewModel(
                    recording: .preview,
                    apiClient: .preview,
                    audioPlayer: PreviewPlaybackPlayer()
                )
                vm.playbackError = APIError.networkUnavailable
                return vm
            }()
        )
    }
}

// MARK: - Preview Helpers

extension Recording {
    static let preview = Recording(
        id: UUID(),
        userId: UUID(),
        subject: "Sunset at the Golden Gate",
        description: "A beautiful evening watching the sun dip below the horizon with the bridge silhouetted against orange and purple clouds.",
        latitude: 37.8199,
        longitude: -122.4783,
        durationSeconds: 134,
        status: .approved,
        createdAt: Date().addingTimeInterval(-3600)
    )
}

extension APIClient {
    static let preview = APIClient(
        baseURL: URL(string: "https://api.hearhere.app/v1")!,
        authInterceptor: AuthInterceptor(tokenProvider: PreviewTokenProvider())
    )
}

private struct PreviewTokenProvider: TokenProviding {
    func currentToken() async throws -> String { "preview-token" }
    func refreshToken() async throws -> String { "preview-token" }
}

private final class PreviewPlaybackPlayer: AudioPlayerProtocol, @unchecked Sendable {
    var state: PlaybackState = .paused
    var currentTime: TimeInterval = 45
    var duration: TimeInterval = 134
    var progress: Double { duration > 0 ? currentTime / duration : 0 }
    func play(url: URL) {}
    func pause() {}
    func resume() {}
    func seek(to time: TimeInterval) async {}
    func stop() {}
}
