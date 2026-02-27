import MapKit
import SwiftUI

/// Full-screen sheet with a draggable pin map, search bar, and location confirmation.
///
/// Allows the user to adjust the recording's pin location by dragging the map,
/// searching for an address, or using their current location.
struct LocationPickerView: View {
    @Binding var selectedCoordinate: CLLocationCoordinate2D?
    var onConfirm: () -> Void

    @State private var cameraPosition: MapCameraPosition
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var pinCoordinate: CLLocationCoordinate2D
    @Environment(\.dismiss) private var dismiss

    init(
        selectedCoordinate: Binding<CLLocationCoordinate2D?>,
        onConfirm: @escaping () -> Void
    ) {
        self._selectedCoordinate = selectedCoordinate
        self.onConfirm = onConfirm
        let initial = selectedCoordinate.wrappedValue ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        self._pinCoordinate = State(initialValue: initial)
        self._cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: initial,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                mapView
                centerPinOverlay
            }
            .safeAreaInset(edge: .bottom) {
                bottomControls
            }
            .searchable(text: $searchText, prompt: "Search for a place")
            .onSubmit(of: .search) {
                Task {
                    await performSearch()
                }
            }
            .onChange(of: searchResults) { _, results in
                if let first = results.first?.placemark.coordinate {
                    pinCoordinate = first
                    cameraPosition = .region(MKCoordinateRegion(
                        center: first,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
            }
            .navigationTitle("Choose Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Cancel location selection")
                }
            }
        }
    }

    // MARK: - Map

    private var mapView: some View {
        Map(position: $cameraPosition) {
            Marker("Recording Location", coordinate: pinCoordinate)
                .tint(.red)
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            pinCoordinate = context.camera.centerCoordinate
        }
        .ignoresSafeArea(edges: .bottom)
        .accessibilityLabel("Map for selecting recording location")
    }

    private var centerPinOverlay: some View {
        Image(systemName: "mappin")
            .font(.title)
            .foregroundStyle(.red)
            .shadow(radius: 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 12) {
            Button {
                useCurrentLocation()
            } label: {
                Label("Use Current Location", systemImage: "location.fill")
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Use current location")
            .accessibilityHint("Centers the pin on your current location")

            Button {
                selectedCoordinate = pinCoordinate
                onConfirm()
            } label: {
                Text("Confirm Location")
                    .font(.body)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Confirm location")
            .accessibilityHint("Saves this location for your recording")
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Search

    private func performSearch() async {
        guard !searchText.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.resultTypes = .address

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            searchResults = response.mapItems
        } catch {
            searchResults = []
        }
    }

    private func useCurrentLocation() {
        let manager = CLLocationManager()
        if let location = manager.location {
            pinCoordinate = location.coordinate
            cameraPosition = .region(MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
    }
}

// MARK: - Previews

#Preview {
    LocationPickerView(
        selectedCoordinate: .constant(CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)),
        onConfirm: {}
    )
}
