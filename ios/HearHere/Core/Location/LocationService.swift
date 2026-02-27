import CoreLocation
import Foundation
import Observation

/// Permission states for location access, forming a state machine.
///
/// Mirrors `CLAuthorizationStatus` with app-specific semantics
/// to drive UI prompts and feature availability.
enum LocationPermission: Sendable {
    /// The user has not yet been asked for location permission.
    case notDetermined

    /// The user has denied location access.
    case denied

    /// Location access is restricted by device policy (e.g., parental controls).
    case restricted

    /// The app has "When In Use" authorization.
    case authorizedWhenInUse

    /// Initializes from a Core Location authorization status.
    init(from status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        case .authorizedWhenInUse, .authorizedAlways:
            self = .authorizedWhenInUse
        @unknown default:
            self = .notDetermined
        }
    }

    /// Whether the app currently has location permission.
    var isAuthorized: Bool {
        self == .authorizedWhenInUse
    }
}

/// The accuracy mode for location updates, matching use case requirements.
///
/// Recording requires high accuracy for precise pin placement, while
/// discovery can use lower accuracy to conserve battery.
enum LocationAccuracy: Sendable {
    /// High accuracy for recording pin placement. Uses `kCLLocationAccuracyBest`.
    case bestForRecording

    /// Reduced accuracy for discovery map. Uses `kCLLocationAccuracyHundredMeters`.
    case hundredMetersForDiscovery
}

/// Protocol for location services, enabling mock injection for testing.
protocol LocationServiceProtocol: Sendable {
    /// The user's most recently determined location, or `nil` if unknown.
    var currentLocation: CLLocation? { get }

    /// The current location permission state.
    var permission: LocationPermission { get }

    /// Requests "When In Use" location authorization from the user.
    func requestWhenInUseAuthorization()

    /// Starts receiving location updates at the specified accuracy.
    /// - Parameter accuracy: The desired accuracy mode.
    func startUpdating(accuracy: LocationAccuracy)

    /// Stops receiving location updates to conserve battery.
    func stopUpdating()
}

/// Wraps `CLLocationManager` to provide an observable, protocol-based location service.
///
/// Manages the location permission state machine and provides the current
/// user location for map centering, nearby queries, and recording pin placement.
/// Uses `kCLLocationAccuracyBest` during recording and `kCLLocationAccuracyHundredMeters`
/// for discovery to balance accuracy with battery life.
@Observable
final class LocationService: NSObject, @unchecked Sendable, LocationServiceProtocol {
    private(set) var currentLocation: CLLocation?
    private(set) var permission: LocationPermission = .notDetermined

    private let manager: CLLocationManager

    /// Creates a location service wrapping a new `CLLocationManager`.
    override init() {
        self.manager = CLLocationManager()
        super.init()
        manager.delegate = self
        permission = LocationPermission(from: manager.authorizationStatus)
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating(accuracy: LocationAccuracy) {
        switch accuracy {
        case .bestForRecording:
            manager.desiredAccuracy = kCLLocationAccuracyBest
        case .hundredMetersForDiscovery:
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        permission = LocationPermission(from: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location errors are non-fatal; the UI shows the last known location
        // or a "location unavailable" state based on currentLocation being nil.
    }
}
