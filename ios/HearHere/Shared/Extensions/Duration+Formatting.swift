import Foundation

extension TimeInterval {
    /// Formats the time interval as MM:SS for audio duration display.
    ///
    /// Example: 154.3 seconds becomes "2:34".
    var mmssFormatted: String {
        let totalSeconds = Int(max(0, self))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

extension Duration {
    /// Formats the duration as MM:SS for audio duration display.
    ///
    /// Example: 154 seconds becomes "2:34".
    var mmssFormatted: String {
        let total = components
        let totalSeconds = Int(total.seconds)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
