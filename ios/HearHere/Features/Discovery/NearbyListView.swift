import SwiftUI

/// List of nearby recordings sorted by distance.
///
/// Shown as a bottom sheet on the discovery map. Each row displays
/// the subject, distance, duration, and creator name. Supports
/// pull-to-refresh and shows an empty state illustration when
/// no recordings are found.
struct NearbyListView: View {
    let recordings: [Recording]
    let isLoading: Bool
    let onSelect: (Recording) -> Void
    let onRefresh: () async -> Void

    /// Binding to the search radius for the slider in the header.
    @Binding var searchRadius: Double

    var body: some View {
        Group {
            if recordings.isEmpty && !isLoading {
                emptyState
            } else {
                recordingsList
            }
        }
    }

    private var recordingsList: some View {
        List {
            radiusSection

            Section {
                ForEach(sortedRecordings) { recording in
                    Button {
                        onSelect(recording)
                    } label: {
                        recordingRow(recording)
                    }
                    .accessibilityHint("Opens playback for this recording")
                }
            } header: {
                Text("\(recordings.count) nearby")
                    .font(.caption)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await onRefresh()
        }
        .overlay {
            if isLoading && recordings.isEmpty {
                ProgressView("Loading nearby recordings...")
            }
        }
    }

    private var radiusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                Text("Search Radius: \(Int(searchRadius))m")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                Slider(
                    value: $searchRadius,
                    in: MapViewModel.minRadius...MapViewModel.maxRadius,
                    step: 50
                )
                .accessibilityLabel("Search radius")
                .accessibilityValue("\(Int(searchRadius)) meters")
            }
            .padding(.vertical, Theme.spacingXS)
        }
    }

    private func recordingRow(_ recording: Recording) -> some View {
        HStack(spacing: Theme.spacingSM) {
            // Waveform icon
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: Theme.minTapTarget, height: Theme.minTapTarget)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                Text(recording.subject)
                    .font(.body.weight(.medium))
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

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(recording.subject), \(recording.formattedDistance ?? "nearby"), \(recording.formattedDuration)")
    }

    private var emptyState: some View {
        VStack(spacing: Theme.spacingMD) {
            Image(systemName: "map.circle")
                .font(.system(size: 56))
                .foregroundStyle(Theme.secondary.opacity(0.5))
                .accessibilityHidden(true)

            Text("No stories nearby yet")
                .font(.title3.weight(.semibold))

            Text("Be the first to record one!")
                .font(.body)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No stories nearby yet. Be the first to record one.")
    }

    private var sortedRecordings: [Recording] {
        recordings.sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
    }
}

// MARK: - Previews

#Preview("Populated") {
    NearbyListView(
        recordings: Recording.previewList,
        isLoading: false,
        onSelect: { _ in },
        onRefresh: {},
        searchRadius: .constant(500)
    )
}

#Preview("Empty") {
    NearbyListView(
        recordings: [],
        isLoading: false,
        onSelect: { _ in },
        onRefresh: {},
        searchRadius: .constant(500)
    )
}

#Preview("Loading") {
    NearbyListView(
        recordings: [],
        isLoading: true,
        onSelect: { _ in },
        onRefresh: {},
        searchRadius: .constant(500)
    )
}
