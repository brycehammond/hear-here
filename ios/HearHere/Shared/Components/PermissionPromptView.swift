import SwiftUI

/// The type of permission being requested, driving the prompt's content.
enum PermissionType {
    case microphone
    case location
    case notifications

    var title: String {
        switch self {
        case .microphone:
            return "Microphone Access"
        case .location:
            return "Location Access"
        case .notifications:
            return "Notifications"
        }
    }

    var explanation: String {
        switch self {
        case .microphone:
            return "Hear Here needs microphone access to record your stories and share them with the community."
        case .location:
            return "Hear Here uses your location to show nearby recordings and pin your stories to the map."
        case .notifications:
            return "Get notified when your recording is approved and ready for others to discover."
        }
    }

    var iconName: String {
        switch self {
        case .microphone:
            return "mic.circle.fill"
        case .location:
            return "location.circle.fill"
        case .notifications:
            return "bell.circle.fill"
        }
    }

    var buttonTitle: String {
        switch self {
        case .microphone, .location, .notifications:
            return "Continue"
        }
    }
}

/// Generic pre-prompt screen shown before triggering a system permission dialog.
///
/// Displays an illustration, explanation text, and a "Continue" button. Parameterized
/// for microphone, location, and notification permissions.
struct PermissionPromptView: View {
    let permissionType: PermissionType
    let onContinue: () -> Void

    /// When true, the permission has been denied and we show a settings redirect instead.
    var isDenied: Bool = false

    var body: some View {
        VStack(spacing: Theme.spacingLG) {
            Spacer()

            Image(systemName: permissionType.iconName)
                .font(.system(size: 72))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)

            Text(permissionType.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text(permissionType.explanation)
                .font(.body)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacingLG)

            Spacer()

            if isDenied {
                VStack(spacing: Theme.spacingSM) {
                    Text("Permission was denied. You can enable it in Settings.")
                        .font(.callout)
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)

                    Button("Open Settings") {
                        #if os(iOS)
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                        #endif
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityHint("Opens the system Settings app to change permissions")
                }
                .padding(.horizontal, Theme.spacingLG)
            } else {
                Button(permissionType.buttonTitle) {
                    onContinue()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Theme.spacingLG)
                .accessibilityHint("Triggers the system permission dialog for \(permissionType.title.lowercased())")
            }

            Spacer()
                .frame(height: Theme.spacingXL)
        }
    }
}

// MARK: - Previews

#Preview("Microphone") {
    PermissionPromptView(permissionType: .microphone) {}
}

#Preview("Location") {
    PermissionPromptView(permissionType: .location) {}
}

#Preview("Notifications") {
    PermissionPromptView(permissionType: .notifications) {}
}

#Preview("Denied State") {
    PermissionPromptView(permissionType: .microphone, onContinue: {}, isDenied: true)
}
