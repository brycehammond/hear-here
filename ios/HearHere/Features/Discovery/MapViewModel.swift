import CoreLocation
import Observation
import SwiftUI

/// Manages the state for the discovery map, including nearby recordings,
/// search radius, and selected recording.
///
/// Loads nearby recordings via the API client based on the user's current
/// location and configurable search radius.
@Observable
@MainActor
final class MapViewModel {
    /// The list of nearby recordings loaded from the API.
    var recordings: [Recording] = []

    /// The currently selected recording for callout display.
    var selectedRecording: Recording?

    /// Whether recordings are being loaded.
    var isLoading = false

    /// An error message to display, if any.
    var error: String?

    /// The search radius in meters. Default 500m, range 50-5000m.
    var searchRadius: Double = 500

    /// The minimum allowed search radius in meters.
    static let minRadius: Double = 50

    /// The maximum allowed search radius in meters.
    static let maxRadius: Double = 5000

    private let apiClient: APIClient
    private let locationService: any LocationServiceProtocol

    init(apiClient: APIClient, locationService: any LocationServiceProtocol) {
        self.apiClient = apiClient
        self.locationService = locationService
    }

    /// Loads nearby recordings from the API using the current location and search radius.
    func loadNearby() async {
        guard let location = locationService.currentLocation else {
            error = "Location unavailable. Please enable location services."
            return
        }

        isLoading = true
        error = nil

        do {
            let response = try await apiClient.request(
                .nearbyRecordings(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    radiusMeters: searchRadius,
                    cursor: nil
                ),
                type: PaginatedResponse<NearbyRecordingResponse>.self
            )
            recordings = response.items.map { $0.toDomain() }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    /// Selects a recording for callout display on the map.
    func selectRecording(_ recording: Recording?) {
        selectedRecording = recording
    }

    /// The user's current location coordinate, if available.
    var userCoordinate: CLLocationCoordinate2D? {
        locationService.currentLocation?.coordinate
    }
}
