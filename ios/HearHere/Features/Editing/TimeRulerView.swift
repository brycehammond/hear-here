import SwiftUI

/// Time markers that scroll horizontally with the waveform.
///
/// Draws time labels (0:00, 0:15, 0:30, etc.) using Canvas for performance.
/// Scales tick density based on zoom level.
struct TimeRulerView: View {
    let duration: TimeInterval
    let zoomLevel: CGFloat
    let scrollOffset: CGFloat

    private let rulerHeight: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                drawRuler(context: context, size: size, availableWidth: geometry.size.width)
            }
        }
        .frame(height: rulerHeight)
    }

    private func drawRuler(context: GraphicsContext, size: CGSize, availableWidth: CGFloat) {
        guard duration > 0 else { return }

        let totalWidth = availableWidth * zoomLevel
        let interval = tickInterval(for: totalWidth)

        var time: TimeInterval = 0
        while time <= duration {
            let x = CGFloat(time / duration) * totalWidth - scrollOffset

            if x >= -50, x <= size.width + 50 {
                // Tick mark
                var tickPath = Path()
                tickPath.move(to: CGPoint(x: x, y: size.height - 6))
                tickPath.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(tickPath, with: .color(Theme.onSurfaceSecondary), lineWidth: 1)

                // Time label
                let label = formatRulerTime(time)
                let text = Text(label).font(.system(size: 9)).foregroundColor(Theme.onSurfaceSecondary)
                context.draw(
                    context.resolve(text),
                    at: CGPoint(x: x, y: size.height - 12),
                    anchor: .bottom
                )
            }

            time += interval
        }
    }

    private func tickInterval(for totalWidth: CGFloat) -> TimeInterval {
        let pixelsPerSecond = totalWidth / CGFloat(duration)

        // Choose interval so ticks aren't too dense or sparse
        let intervals: [TimeInterval] = [1, 2, 5, 10, 15, 30, 60]
        for interval in intervals {
            if pixelsPerSecond * CGFloat(interval) >= 40 {
                return interval
            }
        }
        return 60
    }

    private func formatRulerTime(_ time: TimeInterval) -> String {
        let total = Int(time)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
