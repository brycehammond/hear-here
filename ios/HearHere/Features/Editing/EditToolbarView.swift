import SwiftUI

/// Horizontal toolbar with audio editing actions.
///
/// Buttons include undo, redo, trim, cut, fade in, fade out, and normalize.
/// Trim/Cut are disabled when no selection range is active. Undo/Redo reflect
/// the current session state.
struct EditToolbarView: View {
    let canUndo: Bool
    let canRedo: Bool
    let canTrimOrCut: Bool

    let onUndo: () -> Void
    let onRedo: () -> Void
    let onTrim: () -> Void
    let onCut: () -> Void
    let onFadeIn: () -> Void
    let onFadeOut: () -> Void
    let onNormalize: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.spacingSM) {
                toolButton("Undo", icon: "arrow.uturn.backward", enabled: canUndo, action: onUndo)
                toolButton("Redo", icon: "arrow.uturn.forward", enabled: canRedo, action: onRedo)

                Divider()
                    .frame(height: 28)

                toolButton("Trim", icon: "scissors", enabled: canTrimOrCut, action: onTrim)
                toolButton("Cut", icon: "cut", enabled: canTrimOrCut, action: onCut)

                Divider()
                    .frame(height: 28)

                toolButton("Fade In", icon: "chart.line.uptrend.xyaxis", enabled: true, action: onFadeIn)
                toolButton("Fade Out", icon: "chart.line.downtrend.xyaxis", enabled: true, action: onFadeOut)
                toolButton("Normalize", icon: "waveform.badge.magnifyingglass", enabled: true, action: onNormalize)
            }
            .padding(.horizontal, Theme.spacingMD)
        }
        .frame(height: Theme.minTapTarget + Theme.spacingSM)
        .background(Theme.surfaceSecondary)
    }

    private func toolButton(
        _ label: String,
        icon: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.caption2)
            }
            .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
        }
        .disabled(!enabled)
        .foregroundStyle(enabled ? Theme.accent : Theme.onSurfaceSecondary)
        .accessibilityLabel(label)
    }
}
