import Observation
import SwiftUI

/// Manages navigation within the Discovery tab.
///
/// Controls the navigation path and provides methods to push destinations
/// like the playback view for a selected recording.
@Observable
@MainActor
final class DiscoveryCoordinator {
    /// Possible navigation destinations within the Discovery tab.
    enum Destination: Hashable {
        case playback(Recording)
    }

    /// The navigation path for this tab's NavigationStack.
    var path = NavigationPath()

    /// Navigates to the playback screen for the given recording.
    func showPlayback(_ recording: Recording) {
        path.append(Destination.playback(recording))
    }

    /// Pops to the root map view.
    func popToRoot() {
        path.removeLast(path.count)
    }
}
