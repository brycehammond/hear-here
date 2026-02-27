import SwiftUI

/// Manages navigation state for the profile tab.
///
/// Owns the navigation path and provides methods for pushing to
/// recording detail, settings, and playback destinations.
@Observable
@MainActor
final class ProfileCoordinator {
    var path = NavigationPath()

    enum Destination: Hashable {
        case recordingDetail(Recording)
        case settings
        case playback(Recording)
    }

    func showRecordingDetail(_ recording: Recording) {
        path.append(Destination.recordingDetail(recording))
    }

    func showSettings() {
        path.append(Destination.settings)
    }

    func showPlayback(_ recording: Recording) {
        path.append(Destination.playback(recording))
    }

    func popToRoot() {
        path.removeLast(path.count)
    }
}
