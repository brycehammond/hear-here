import SwiftUI

/// Displays a recording's moderation status with an icon, text label, and semantic color.
///
/// Communicates status via both color AND icon/text for accessibility. The badge
/// adapts to Dynamic Type and provides descriptive VoiceOver labels.
struct StatusBadge: View {
    let status: ModerationStatus

    var body: some View {
        Label(status.displayName, systemImage: status.iconName)
            .font(.caption.weight(.medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, Theme.spacingSM)
            .padding(.vertical, Theme.spacingXS)
            .background(foregroundColor.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel("Status: \(status.displayName)")
    }

    private var foregroundColor: Color {
        switch status {
        case .pendingUpload:
            return Theme.warning
        case .pendingModeration, .pendingReview:
            return Theme.warning
        case .approved:
            return Theme.success
        case .rejected:
            return Theme.error
        }
    }
}

// MARK: - Previews

#Preview("All Statuses") {
    VStack(spacing: Theme.spacingSM) {
        StatusBadge(status: .pendingUpload)
        StatusBadge(status: .pendingModeration)
        StatusBadge(status: .pendingReview)
        StatusBadge(status: .approved)
        StatusBadge(status: .rejected)
    }
    .padding()
}

#Preview("Dark Mode") {
    VStack(spacing: Theme.spacingSM) {
        StatusBadge(status: .pendingModeration)
        StatusBadge(status: .approved)
        StatusBadge(status: .rejected)
    }
    .padding()
    .preferredColorScheme(.dark)
}
