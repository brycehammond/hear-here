import CoreLocation

extension CLLocationCoordinate2D: @retroactive Equatable {
    /// Creates a coordinate from latitude and longitude doubles.
    ///
    /// - Parameters:
    ///   - lat: The latitude in degrees.
    ///   - lng: The longitude in degrees.
    public init(lat: Double, lng: Double) {
        self.init(latitude: lat, longitude: lng)
    }

    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
