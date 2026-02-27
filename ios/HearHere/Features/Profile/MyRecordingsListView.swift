import SwiftUI

/// List of the user's recordings with filtering, swipe-to-delete, and pagination.
///
/// Sorted by creation date (newest first). Each row shows subject, date, duration,
/// and a ``StatusBadge``. Includes a segmented filter control for moderation status.
struct MyRecordingsListView: View {
    @Bindable var viewModel: ProfileViewModel
    @Bindable var coordinator: ProfileCoordinator

    var body: some View {
        VStack(spacing: 12) {
            filterControl
            recordingsList
        }
        .alert("Delete Recording?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteRecording()
                }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
        } message: {
            Text("This action cannot be undone. The recording will be permanently deleted.")
        }
    }

    // MARK: - Filter Control

    private var filterControl: some View {
        Picker("Filter", selection: $viewModel.selectedFilter) {
            ForEach(RecordingFilter.allCases) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Filter recordings by status")
    }

    // MARK: - Recordings List

    @ViewBuilder
    private var recordingsList: some View {
        if viewModel.isLoadingRecordings && viewModel.recordings.isEmpty {
            loadingView
        } else if let error = viewModel.recordingsError, viewModel.recordings.isEmpty {
            errorView(error: error)
        } else if viewModel.filteredRecordings.isEmpty {
            emptyView
        } else {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.filteredRecordings) { recording in
                    recordingRow(recording)
                        .onAppear {
                            if recording.id == viewModel.filteredRecordings.last?.id {
                                Task {
                                    await viewModel.loadMoreRecordings()
                                }
                            }
                        }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .padding()
                        .accessibilityLabel("Loading more recordings")
                }
            }
        }
    }

    private func recordingRow(_ recording: Recording) -> some View {
        Button {
            coordinator.showRecordingDetail(recording)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recording.subject)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(formatDate(recording.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(recording.formattedDuration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                StatusBadge(status: recording.status)
            }
            .padding(.vertical, 12)
            .padding(.horizontal)
            .frame(minHeight: 44)
            .background(Theme.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel("\(recording.subject), \(recording.status.displayName), \(recording.formattedDuration)")
        .accessibilityHint("Tap to view recording details")
        .contextMenu {
            Button(role: .destructive) {
                viewModel.confirmDelete(recording)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                viewModel.confirmDelete(recording)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityLabel("Delete recording")
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading recordings...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityLabel("Loading recordings")
    }

    private func errorView(error: Error) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("Could not load recordings")
                .font(.subheadline)
                .fontWeight(.medium)

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task {
                    await viewModel.loadRecordings()
                }
            }
            .frame(minHeight: 44)
            .accessibilityLabel("Retry loading recordings")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            if viewModel.selectedFilter == .all {
                Text("No recordings yet")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Your recordings will appear here after you create them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("No \(viewModel.selectedFilter.rawValue.lowercased()) recordings")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Previews

#Preview("Populated") {
    MyRecordingsListView(
        viewModel: {
            let vm = ProfileViewModel(apiClient: .preview)
            vm.recordings = [
                Recording(
                    id: UUID(), userId: UUID(),
                    subject: "Morning at the market",
                    description: "Vendors setting up at dawn.",
                    latitude: 37.78, longitude: -122.41,
                    durationSeconds: 180, status: .approved,
                    createdAt: Date().addingTimeInterval(-3600)
                ),
                Recording(
                    id: UUID(), userId: UUID(),
                    subject: "Ocean waves",
                    description: nil,
                    latitude: 37.77, longitude: -122.51,
                    durationSeconds: 240, status: .pendingModeration,
                    createdAt: Date().addingTimeInterval(-7200)
                ),
                Recording(
                    id: UUID(), userId: UUID(),
                    subject: "Jazz in the park",
                    description: "A wonderful performance.",
                    latitude: 37.77, longitude: -122.45,
                    durationSeconds: 120, status: .rejected,
                    createdAt: Date().addingTimeInterval(-86400)
                ),
            ]
            return vm
        }(),
        coordinator: ProfileCoordinator()
    )
}

#Preview("Empty") {
    MyRecordingsListView(
        viewModel: ProfileViewModel(apiClient: .preview),
        coordinator: ProfileCoordinator()
    )
}

#Preview("Loading") {
    MyRecordingsListView(
        viewModel: {
            let vm = ProfileViewModel(apiClient: .preview)
            vm.isLoadingRecordings = true
            return vm
        }(),
        coordinator: ProfileCoordinator()
    )
}

#Preview("Error") {
    MyRecordingsListView(
        viewModel: {
            let vm = ProfileViewModel(apiClient: .preview)
            vm.recordingsError = APIError.networkUnavailable
            return vm
        }(),
        coordinator: ProfileCoordinator()
    )
}
