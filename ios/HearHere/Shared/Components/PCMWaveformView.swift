import SwiftUI

/// High-resolution waveform renderer using SwiftUI Canvas.
///
/// Draws only visible samples based on scroll offset and zoom level for performance.
/// Supports pinch-to-zoom, pan/scroll, tap-to-seek, selection highlighting, and a
/// playhead cursor.
struct PCMWaveformView: View {
    let peaks: [Float]
    let duration: TimeInterval

    @Binding var currentTime: TimeInterval
    @Binding var selectionRange: ClosedRange<TimeInterval>?

    var zoomLevel: CGFloat = 1.0
    var scrollOffset: CGFloat = 0

    var onSeek: ((TimeInterval) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width * zoomLevel
            let height = geometry.size.height

            Canvas { context, size in
                drawWaveform(context: context, size: size, totalWidth: totalWidth, height: height)
                drawSelection(context: context, size: size, totalWidth: totalWidth, height: height)
                drawPlayhead(context: context, size: size, totalWidth: totalWidth, height: height)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let time = timeForX(location.x, totalWidth: totalWidth)
                onSeek?(time)
            }
        }
        .accessibilityRepresentation {
            Text(accessibilityDescription)
        }
    }

    // MARK: - Drawing

    private func drawWaveform(context: GraphicsContext, size: CGSize, totalWidth: CGFloat, height: CGFloat) {
        guard !peaks.isEmpty, duration > 0 else { return }

        let visibleStartX = scrollOffset
        let visibleEndX = scrollOffset + size.width

        let centerY = height / 2
        let maxBarHeight = height * 0.9

        let samplesPerPoint = CGFloat(peaks.count) / totalWidth
        let startSample = max(0, Int(visibleStartX * samplesPerPoint))
        let endSample = min(peaks.count, Int(visibleEndX * samplesPerPoint) + 1)

        guard startSample < endSample else { return }

        var path = Path()

        // Draw top half
        for i in startSample..<endSample {
            let x = CGFloat(i) / CGFloat(peaks.count) * totalWidth - scrollOffset
            let amplitude = CGFloat(peaks[i])
            let barHeight = amplitude * maxBarHeight / 2

            path.move(to: CGPoint(x: x, y: centerY - barHeight))
            path.addLine(to: CGPoint(x: x, y: centerY + barHeight))
        }

        context.stroke(path, with: .color(Theme.accent), lineWidth: 1)
    }

    private func drawSelection(context: GraphicsContext, size: CGSize, totalWidth: CGFloat, height: CGFloat) {
        guard let range = selectionRange, duration > 0 else { return }

        let startX = xForTime(range.lowerBound, totalWidth: totalWidth) - scrollOffset
        let endX = xForTime(range.upperBound, totalWidth: totalWidth) - scrollOffset

        let rect = CGRect(
            x: startX,
            y: 0,
            width: endX - startX,
            height: height
        )

        context.fill(Path(rect), with: .color(Theme.accent.opacity(0.2)))
    }

    private func drawPlayhead(context: GraphicsContext, size: CGSize, totalWidth: CGFloat, height: CGFloat) {
        guard duration > 0 else { return }

        let x = xForTime(currentTime, totalWidth: totalWidth) - scrollOffset

        guard x >= 0, x <= size.width else { return }

        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: height))

        context.stroke(path, with: .color(Theme.primary), lineWidth: 2)
    }

    // MARK: - Coordinate Mapping

    private func xForTime(_ time: TimeInterval, totalWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * totalWidth
    }

    private func timeForX(_ x: CGFloat, totalWidth: CGFloat) -> TimeInterval {
        guard totalWidth > 0 else { return 0 }
        let adjustedX = x + scrollOffset
        return max(0, min(duration, TimeInterval(adjustedX / totalWidth) * duration))
    }

    private var accessibilityDescription: String {
        if peaks.isEmpty {
            return "Audio waveform, no data loaded"
        }
        if let range = selectionRange {
            return "Audio waveform with selection from \(Int(range.lowerBound)) to \(Int(range.upperBound)) seconds"
        }
        return "Audio waveform, \(Int(duration)) seconds"
    }
}
