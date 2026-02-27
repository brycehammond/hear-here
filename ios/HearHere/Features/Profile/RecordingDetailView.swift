import MapKit
import SwiftUI

/// Full detail view for a single recording showing metadata, map, status, and audio preview.
///
/// Shows a prominent ``StatusBadge`` with explanation text appropriate to the current
/// moderation status. Allows audio playback regardless of status (owners can hear their
/// own recordings). Includes a delete button with confirmation.
struct RecordingDetailView: View {
    let recording: Recording
    @Bindable var viewModel: ProfileViewModel
    @State private var showDeleteAlert = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statusSection
                detailsSection
                mapSection
                audioSection
                deleteSection
            }
            .padding()
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Recording?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                Task {
                    viewModel.recordingToDelete = recording
                    await viewModel.deleteRecording()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. The recording will be permanently deleted.")
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StatusBadge(status: recording.status)
                Spacer()
            }

            Text(statusExplanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Status explanation: \(statusExplanation)")
        }
        .padding()
        .background(statusBackgroundColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statusExplanation: String {
        switch recording.status {
        case .pendingUpload:
            return "Your recording is being uploaded."
        case .pendingModeration, .pendingReview:
            return "Your recording is being reviewed. This usually takes less than an hour."
        case .approved:
            return "Your recording is live and discoverable by others nearby."
        case .rejected:
            return "Your recording did not meet our community guidelines."
        }
    }

    private var statusBackgroundColor: Color {
        switch recording.status {
        case .pendingUpload, .pendingModeration, .pendingReview:
            return .orange
        case .approved:
            return .green
        case .rejected:
            return .red
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recording.subject)
                .font(.title2)
                .fontWeight(.bold)
                .accessibilityLabel("Subject: \(recording.subject)")

            if let description = recording.description, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Description: \(description)")
            }

            HStack(spacing: 16) {
                Label(recording.formattedDuration, systemImage: "waveform")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Duration: \(recording.formattedDuration)")

                Label(formatDate(recording.createdAt), systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Created: \(formatDate(recording.createdAt))")
            }
        }
    }

    // MARK: - Map Section

    private var mapSection: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: recording.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        ))) {
            Marker(recording.subject, coordinate: recording.coordinate)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
        .accessibilityLabel("Map showing recording location")
    }

    // MARK: - Audio Section

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio Preview")
                .font(.headline)

            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.accentColor)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Play recording preview")
                    .accessibilityHint("Plays back your recording")

                VStack(alignment: .leading) {
                    Text(recording.subject)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(recording.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(Theme.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Delete Section

    private var deleteSection: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.vertical, 8)

            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label("Delete Recording", systemImage: "trash")
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Delete recording")
            .accessibilityHint("Permanently deletes this recording")
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Previews

#Preview("Approved") {
    NavigationStack {
        RecordingDetailView(
            recording: Recording(
                id: UUID(), userId: UUID(),
                subject: "Sunset at the Golden Gate",
                description: "A beautiful evening watching the sun dip below the horizon.",
                latitude: 37.8199, longitude: -122.4783,
                durationSeconds: 134, status: .approved,
                createdAt: Date().addingTimeInterval(-3600)
            ),
            viewModel: ProfileViewModel(apiClient: .preview)
        )
    }
}

#Preview("Under Review") {
    NavigationStack {
        RecordingDetailView(
            recording: Recording(
                id: UUID(), userId: UUID(),
                subject: "Birds in the morning",
                description: "Recorded at dawn in Golden Gate Park.",
                latitude: 37.77, longitude: -122.46,
                durationSeconds: 240, status: .pendingModeration,
                createdAt: Date().addingTimeInterval(-1800)
            ),
            viewModel: ProfileViewModel(apiClient: .preview)
        )
    }
}

#Preview("Rejected") {
    NavigationStack {
        RecordingDetailView(
            recording: Recording(
                id: UUID(), userId: UUID(),
                subject: "Rejected recording",
                description: "This one did not pass review.",
                latitude: 37.78, longitude: -122.42,
                durationSeconds: 60, status: .rejected,
                createdAt: Date().addingTimeInterval(-86400)
            ),
            viewModel: ProfileViewModel(apiClient: .preview)
        )
    }
}
