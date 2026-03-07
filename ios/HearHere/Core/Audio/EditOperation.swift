import Foundation

enum EditOperation: Equatable, Sendable {
    case trim(start: TimeInterval, end: TimeInterval)
    case cut(start: TimeInterval, end: TimeInterval)
    case fadeIn(duration: TimeInterval)
    case fadeOut(duration: TimeInterval)
    case normalize(targetPeakDb: Float)
}
