import SwiftUI

/// A real-time input level meter that displays audio levels as a horizontal bar
/// with a green-to-yellow-to-red gradient, plus a clipping indicator.
struct InputLevelMeter: View {
    /// Normalized audio level from 0.0 (silence) to 1.0 (full scale).
    let level: Float

    /// Whether the input is currently clipping.
    let isClipping: Bool

    /// The clipping threshold as a normalized value (~-1 dB).
    static let clippingThreshold: Float = 0.98

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))

                    // Level bar with gradient
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.green, .yellow, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(level))
                }
            }
            .frame(height: 8)

            // Clipping indicator
            Circle()
                .fill(isClipping ? Color.red : Color.gray.opacity(0.3))
                .frame(width: 10, height: 10)
                .opacity(isClipping ? 1.0 : 0.5)
                .animation(.easeInOut(duration: 0.1), value: isClipping)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let percentage = Int(level * 100)
        if isClipping {
            return "Input level \(percentage) percent, clipping"
        }
        return "Input level \(percentage) percent"
    }

    // MARK: - Static Helpers

    /// Normalizes a decibel value from AVAudioRecorder's range (-60...0) to 0.0...1.0.
    static func normalizeDecibels(_ decibels: Float) -> Float {
        let minDb: Float = -60
        let clamped = max(minDb, min(0, decibels))
        return (clamped - minDb) / (0 - minDb)
    }

    /// Returns whether the given dB level indicates clipping (above ~-1 dB).
    static func isClipping(decibelLevel: Float) -> Bool {
        normalizeDecibels(decibelLevel) >= clippingThreshold
    }
}

#Preview("Low Level") {
    InputLevelMeter(level: 0.3, isClipping: false)
        .padding()
}

#Preview("High Level") {
    InputLevelMeter(level: 0.85, isClipping: false)
        .padding()
}

#Preview("Clipping") {
    InputLevelMeter(level: 0.99, isClipping: true)
        .padding()
}
