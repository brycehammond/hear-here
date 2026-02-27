import SwiftUI

/// Custom map annotation view displaying a circular waveform icon.
///
/// Color intensity is based on the recording's recency: newer recordings
/// appear more vivid, while older recordings are more subdued. Meets the
/// 44x44pt minimum tap target for accessibility.
struct RecordingPinView: View {
    let recording: Recording
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(pinColor.opacity(isSelected ? 1 : opacityForRecency))
                .frame(width: pinSize, height: pinSize)
                .shadow(color: pinColor.opacity(0.3), radius: isSelected ? 6 : 3)

            Image(systemName: "waveform")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
        .accessibilityLabel("\(recording.subject), \(recording.formattedDistance ?? "nearby"), \(recording.formattedDuration)")
        .accessibilityHint("Tap to see details about this recording")
        .accessibilityAddTraits(.isButton)
    }

    private var pinSize: CGFloat {
        isSelected ? 40 : 32
    }

    private var pinColor: Color {
        Theme.accent
    }

    /// Calculates opacity based on how recent the recording is.
    /// Recordings from the last hour are fully opaque; older ones fade.
    private var opacityForRecency: Double {
        let age = Date().timeIntervalSince(recording.createdAt)
        let oneHour: TimeInterval = 3600
        let oneWeek: TimeInterval = 604800

        if age < oneHour {
            return 1.0
        } else if age < oneWeek {
            // Linear fade from 1.0 to 0.5 over a week
            let normalized = (age - oneHour) / (oneWeek - oneHour)
            return 1.0 - (normalized * 0.5)
        } else {
            return 0.5
        }
    }
}

// MARK: - Previews

#Preview("Recent Recording") {
    RecordingPinView(recording: .preview, isSelected: false)
        .padding()
}

#Preview("Selected") {
    RecordingPinView(recording: .preview, isSelected: true)
        .padding()
}

#Preview("Old Recording") {
    let old = Recording(
        id: UUID(),
        userId: UUID(),
        subject: "Old Story",
        description: nil,
        latitude: 37.7749,
        longitude: -122.4194,
        durationSeconds: 60,
        status: .approved,
        createdAt: Date().addingTimeInterval(-604800 * 2),
        distanceMeters: 200
    )
    RecordingPinView(recording: old, isSelected: false)
        .padding()
}
