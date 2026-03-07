import SwiftUI

/// Manages navigation state for the recording flow.
///
/// The coordinator owns the navigation path and provides methods to push
/// destinations in the recording flow: record -> metadata -> location picker -> confirmation.
@Observable
@MainActor
final class RecordingCoordinator {
    var path = NavigationPath()
    var showLocationPicker = false

    enum Destination: Hashable {
        case editing
        case metadata
        case confirmation
    }

    func showEditing() {
        path.append(Destination.editing)
    }

    func showMetadata() {
        path.append(Destination.metadata)
    }

    func showConfirmation() {
        path.append(Destination.confirmation)
    }

    func presentLocationPicker() {
        showLocationPicker = true
    }

    func dismissLocationPicker() {
        showLocationPicker = false
    }

    func popToRoot() {
        path.removeLast(path.count)
    }
}
