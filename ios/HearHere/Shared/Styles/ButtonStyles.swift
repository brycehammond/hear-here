import SwiftUI

/// Filled button with accent color background and white label.
///
/// Meets the 44pt minimum tap target requirement and scales with Dynamic Type.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.minTapTarget)
            .padding(.horizontal, Theme.spacingMD)
            .background(Theme.accent.opacity(isEnabled ? 1 : 0.4))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Outlined button with accent-colored border and label.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.accent.opacity(isEnabled ? 1 : 0.4))
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.minTapTarget)
            .padding(.horizontal, Theme.spacingMD)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMD)
                    .stroke(Theme.accent.opacity(isEnabled ? 1 : 0.4), lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Red-tinted button for destructive actions.
struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.minTapTarget)
            .padding(.horizontal, Theme.spacingMD)
            .background(Theme.error.opacity(isEnabled ? 1 : 0.4))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Previews

#Preview("Button Styles") {
    VStack(spacing: Theme.spacingMD) {
        Button("Primary Action") {}
            .buttonStyle(PrimaryButtonStyle())

        Button("Secondary Action") {}
            .buttonStyle(SecondaryButtonStyle())

        Button("Delete") {}
            .buttonStyle(DestructiveButtonStyle())

        Button("Disabled Primary") {}
            .buttonStyle(PrimaryButtonStyle())
            .disabled(true)

        Button("Disabled Secondary") {}
            .buttonStyle(SecondaryButtonStyle())
            .disabled(true)
    }
    .padding()
}
