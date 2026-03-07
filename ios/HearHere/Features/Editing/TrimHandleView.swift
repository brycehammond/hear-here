import SwiftUI

/// Draggable handle for adjusting trim selection boundaries.
///
/// Displays a vertical bar with a grab indicator. Provides haptic feedback
/// on drag start via ``UIImpactFeedbackGenerator``.
struct TrimHandleView: View {
    enum Side {
        case left, right
    }

    let side: Side
    let onDrag: (DragGesture.Value) -> Void
    let onDragEnd: () -> Void

    @State private var isDragging = false

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Theme.accent)
            .frame(width: 12)
            .overlay {
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 0.5)
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 4, height: 1.5)
                    }
                }
            }
            .contentShape(Rectangle().inset(by: -Theme.spacingSM))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            triggerHaptic()
                        }
                        onDrag(value)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onDragEnd()
                    }
            )
            .accessibilityLabel(side == .left ? "Left trim handle" : "Right trim handle")
            .accessibilityAddTraits(.allowsDirectInteraction)
    }

    private func triggerHaptic() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }
}
