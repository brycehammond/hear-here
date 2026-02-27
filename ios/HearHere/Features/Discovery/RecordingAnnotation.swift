import MapKit
import SwiftUI

/// Data model connecting a ``Recording`` to its map annotation position.
///
/// Wraps a `Recording` to provide the `Identifiable` and coordinate
/// information needed by MapKit's `Annotation` view.
struct RecordingAnnotation: Identifiable {
    let recording: Recording

    var id: UUID { recording.id }

    var coordinate: CLLocationCoordinate2D { recording.coordinate }
}
