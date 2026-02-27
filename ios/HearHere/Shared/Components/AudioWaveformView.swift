import SwiftUI

/// Animated amplitude bar visualization for audio recording and playback.
///
/// During recording, bars animate based on live amplitude samples. For static
/// display, pass pre-computed samples. Provides an `accessibilityRepresentation`
/// for VoiceOver users describing the audio waveform.
struct AudioWaveformView: View {
    /// Normalized amplitude samples (0.0...1.0).
    let samples: [Float]

    /// The number of bars to display. Samples are down-sampled or padded to fit.
    var barCount: Int = 40

    /// Whether bars should animate (used during live recording).
    var isAnimating: Bool = false

    /// Playback progress from 0.0 to 1.0, used to color played vs. unplayed bars.
    var progress: Double = 0

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                let amplitude = sampleForIndex(index)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barColor(for: index))
                    .frame(width: 3, height: barHeight(for: amplitude))
                    .animation(
                        isAnimating ? .easeInOut(duration: 0.1) : .default,
                        value: amplitude
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .accessibilityRepresentation {
            Text(accessibilityDescription)
        }
    }

    private func sampleForIndex(_ index: Int) -> Float {
        guard !samples.isEmpty else {
            return isAnimating ? Float.random(in: 0.05...0.15) : 0.1
        }
        let sampleIndex = Int(Float(index) / Float(barCount) * Float(samples.count))
        let clampedIndex = min(sampleIndex, samples.count - 1)
        return max(0.05, samples[clampedIndex])
    }

    private func barHeight(for amplitude: Float) -> CGFloat {
        let minHeight: CGFloat = 3
        let maxHeight: CGFloat = 36
        return minHeight + CGFloat(amplitude) * (maxHeight - minHeight)
    }

    private func barColor(for index: Int) -> Color {
        if progress > 0 {
            let progressIndex = Int(progress * Double(barCount))
            return index <= progressIndex ? Theme.accent : Theme.accent.opacity(0.3)
        }
        return Theme.accent.opacity(isAnimating ? 0.8 : 0.5)
    }

    private var accessibilityDescription: String {
        if isAnimating {
            return "Audio waveform, recording in progress"
        } else if progress > 0 {
            let percent = Int(progress * 100)
            return "Audio waveform, \(percent) percent played"
        } else if samples.isEmpty {
            return "Audio waveform, no audio data"
        } else {
            return "Audio waveform visualization"
        }
    }
}

// MARK: - Previews

#Preview("Recording (Animated)") {
    AudioWaveformView(
        samples: (0..<80).map { _ in Float.random(in: 0.1...0.9) },
        isAnimating: true
    )
    .padding()
}

#Preview("Playback (50% Progress)") {
    AudioWaveformView(
        samples: (0..<80).map { _ in Float.random(in: 0.1...0.9) },
        progress: 0.5
    )
    .padding()
}

#Preview("Empty State") {
    AudioWaveformView(samples: [])
        .padding()
}

#Preview("Static Waveform") {
    AudioWaveformView(
        samples: (0..<80).map { _ in Float.random(in: 0.1...0.9) }
    )
    .padding()
}
