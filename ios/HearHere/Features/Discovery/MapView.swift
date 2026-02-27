import MapKit
import SwiftUI

/// Full-screen MapKit map centered on the user's location with recording annotations.
///
/// Displays custom pins for nearby approved recordings, a floating re-center
/// button, and a bottom sheet with ``NearbyListView`` for list-based browsing.
/// Tapping a pin shows a callout with subject, distance, and duration.
struct MapView: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(\.locationService) private var locationService
    @State private var viewModel: MapViewModel?
    @State private var discoveryCoordinator = DiscoveryCoordinator()
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showNearbyList = true
    @State private var selectedAnnotationID: UUID?

    var body: some View {
        NavigationStack(path: $discoveryCoordinator.path) {
            ZStack(alignment: .bottomTrailing) {
                mapContent

                recenterButton
                    .padding(.trailing, Theme.spacingMD)
                    .padding(.bottom, 260)
            }
            .sheet(isPresented: $showNearbyList) {
                nearbySheet
                    .presentationDetents([.fraction(0.3), .medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled)
            }
            .navigationDestination(for: DiscoveryCoordinator.Destination.self) { destination in
                switch destination {
                case .playback(let recording):
                    // Placeholder until PlaybackView is built
                    Text("Playback: \(recording.subject)")
                        .navigationTitle(recording.subject)
                }
            }
            .task {
                let vm = MapViewModel(apiClient: apiClient, locationService: locationService)
                viewModel = vm
                locationService.startUpdating(accuracy: .hundredMetersForDiscovery)
                await vm.loadNearby()
            }
            .onDisappear {
                locationService.stopUpdating()
            }
        }
    }

    @ViewBuilder
    private var mapContent: some View {
        if let viewModel {
            Map(position: $cameraPosition, selection: $selectedAnnotationID) {
                UserAnnotation()

                ForEach(annotations) { annotation in
                    Annotation(
                        annotation.recording.subject,
                        coordinate: annotation.coordinate,
                        anchor: .bottom
                    ) {
                        RecordingPinView(
                            recording: annotation.recording,
                            isSelected: selectedAnnotationID == annotation.id
                        )
                        .onTapGesture {
                            viewModel.selectRecording(annotation.recording)
                            selectedAnnotationID = annotation.id
                        }
                    }
                    .tag(annotation.id)
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .overlay(alignment: .top) {
                if let error = viewModel.error {
                    errorBanner(error)
                }
            }
            .overlay(alignment: .bottom) {
                if let selected = viewModel.selectedRecording {
                    calloutCard(for: selected)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 260)
                }
            }
            .animation(.easeInOut, value: viewModel.selectedRecording?.id)
        } else {
            Map(position: $cameraPosition) {
                UserAnnotation()
            }
        }
    }

    private var recenterButton: some View {
        Button {
            withAnimation {
                cameraPosition = .userLocation(fallback: .automatic)
            }
        } label: {
            Image(systemName: "location.fill")
                .font(.body)
                .foregroundStyle(Theme.accent)
                .frame(width: Theme.minTapTarget, height: Theme.minTapTarget)
                .background(Theme.surface)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .accessibilityLabel("Re-center map on current location")
    }

    private func calloutCard(for recording: Recording) -> some View {
        Button {
            discoveryCoordinator.showPlayback(recording)
            viewModel?.selectRecording(nil)
        } label: {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: Theme.minTapTarget, height: Theme.minTapTarget)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Theme.spacingXS) {
                    Text(recording.subject)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.onSurface)
                        .lineLimit(1)

                    HStack(spacing: Theme.spacingSM) {
                        if let distance = recording.formattedDistance {
                            Text(distance)
                                .font(.caption)
                                .foregroundStyle(Theme.secondary)
                        }
                        Text(recording.formattedDuration)
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
            .padding(Theme.spacingSM)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        }
        .padding(.horizontal, Theme.spacingMD)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(recording.subject), \(recording.formattedDistance ?? "nearby"), \(recording.formattedDuration)")
        .accessibilityHint("Tap to play this recording")
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.spacingMD)
            .padding(.vertical, Theme.spacingSM)
            .background(Theme.error.opacity(0.9))
            .clipShape(Capsule())
            .padding(.top, Theme.spacingSM)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private var nearbySheet: some View {
        if let viewModel {
            NearbyListView(
                recordings: viewModel.recordings,
                isLoading: viewModel.isLoading,
                onSelect: { recording in
                    discoveryCoordinator.showPlayback(recording)
                },
                onRefresh: {
                    await viewModel.loadNearby()
                },
                searchRadius: Binding(
                    get: { viewModel.searchRadius },
                    set: { newValue in
                        viewModel.searchRadius = newValue
                        Task { await viewModel.loadNearby() }
                    }
                )
            )
        }
    }

    private var annotations: [RecordingAnnotation] {
        (viewModel?.recordings ?? []).map { RecordingAnnotation(recording: $0) }
    }
}

// MARK: - Previews

#Preview("Map View") {
    MapView()
}

#Preview("Dark Mode") {
    MapView()
        .preferredColorScheme(.dark)
}
