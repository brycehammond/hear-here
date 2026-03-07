import SwiftUI

/// Scrollable and zoomable waveform editor with trim handles and playhead overlay.
///
/// Wraps ``PCMWaveformView`` and adds left/right ``TrimHandleView`` at the edges
/// of the selection range. Coordinates zoom level, scroll offset, and reports
/// selection changes back to the parent.
struct WaveformEditorView: View {
    let waveformData: WaveformData?
    let duration: TimeInterval

    @Binding var currentTime: TimeInterval
    @Binding var selectionRange: ClosedRange<TimeInterval>?
    @Binding var zoomLevel: CGFloat
    @Binding var scrollOffset: CGFloat

    var onSeek: ((TimeInterval) -> Void)?

    @State private var dragStartOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width * zoomLevel

            ZStack {
                // Waveform
                if let data = waveformData {
                    PCMWaveformView(
                        peaks: data.peaks,
                        duration: duration,
                        currentTime: $currentTime,
                        selectionRange: $selectionRange,
                        zoomLevel: zoomLevel,
                        scrollOffset: scrollOffset,
                        onSeek: onSeek
                    )
                } else {
                    Rectangle()
                        .fill(Theme.surfaceSecondary)
                        .overlay {
                            ProgressView()
                        }
                }

                // Trim handles
                if let range = selectionRange {
                    let startX = xForTime(range.lowerBound, totalWidth: totalWidth, viewWidth: geometry.size.width)
                    let endX = xForTime(range.upperBound, totalWidth: totalWidth, viewWidth: geometry.size.width)

                    TrimHandleView(side: .left) { value in
                        let newTime = timeForX(
                            startX + value.translation.width,
                            totalWidth: totalWidth,
                            viewWidth: geometry.size.width
                        )
                        let clamped = max(0, min(newTime, range.upperBound - 0.1))
                        selectionRange = clamped...range.upperBound
                    } onDragEnd: {}
                        .position(x: startX, y: geometry.size.height / 2)

                    TrimHandleView(side: .right) { value in
                        let newTime = timeForX(
                            endX + value.translation.width,
                            totalWidth: totalWidth,
                            viewWidth: geometry.size.width
                        )
                        let clamped = min(duration, max(newTime, range.lowerBound + 0.1))
                        selectionRange = range.lowerBound...clamped
                    } onDragEnd: {}
                        .position(x: endX, y: geometry.size.height / 2)
                }
            }
            .gesture(panGesture(viewWidth: geometry.size.width))
            .gesture(zoomGesture())
        }
        .frame(height: 160)
        .background(Theme.surfaceTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
    }

    // MARK: - Gestures

    private func panGesture(viewWidth: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation == .zero {
                    dragStartOffset = scrollOffset
                }
                let maxOffset = max(0, viewWidth * zoomLevel - viewWidth)
                scrollOffset = max(0, min(dragStartOffset - value.translation.width, maxOffset))
            }
    }

    private func zoomGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoomLevel = max(1.0, min(value.magnification * zoomLevel, 20.0))
            }
    }

    // MARK: - Coordinate Mapping

    private func xForTime(_ time: TimeInterval, totalWidth: CGFloat, viewWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * totalWidth - scrollOffset
    }

    private func timeForX(_ x: CGFloat, totalWidth: CGFloat, viewWidth: CGFloat) -> TimeInterval {
        guard totalWidth > 0 else { return 0 }
        let adjustedX = x + scrollOffset
        return max(0, min(duration, TimeInterval(adjustedX / totalWidth) * duration))
    }
}
