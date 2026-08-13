import SwiftUI
import MapKit
import CoreLocation
import DunduKit

/// Picks a place for an arrive/leave alert: MKLocalSearch lookup, a recents
/// list, and a current-location shortcut using When In Use permission only —
/// Dundu never asks for Always, because the system fires the geofence, not
/// us (the alarm lives in EventKit).
struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    var onPick: (LocationAlarm) -> Void

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var proximity: LocationAlarm.Proximity = .enter
    @State private var isSearching = false
    @State private var currentLocationError: String?
    @State private var locationFetcher = CurrentLocationFetcher()

    private static let recentsKey = "locationAlarmRecents"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Alert me when I", selection: $proximity) {
                        Text("Arrive").tag(LocationAlarm.Proximity.enter)
                        Text("Leave").tag(LocationAlarm.Proximity.leave)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        Label("Current location", systemImage: "location.fill")
                    }
                    if let currentLocationError {
                        Text(currentLocationError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results, id: \.self) { item in
                            Button {
                                pick(
                                    title: item.name ?? "Location",
                                    coordinate: item.placemark.coordinate
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                                    Text(item.name ?? "Location")
                                    if let locality = item.placemark.locality {
                                        Text(locality)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                let recents = Self.loadRecents()
                if results.isEmpty && !recents.isEmpty {
                    Section("Recent") {
                        ForEach(recents, id: \.title) { recent in
                            Button {
                                pick(
                                    title: recent.title,
                                    coordinate: CLLocationCoordinate2D(
                                        latitude: recent.latitude, longitude: recent.longitude
                                    ),
                                    addToRecents: false
                                )
                            } label: {
                                Label(recent.title, systemImage: "clock")
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search for a place")
            .onChange(of: query) {
                Task { await search() }
            }
            .overlay {
                if isSearching { ProgressView() }
            }
            .dunduFormBackground()
            .navigationTitle("Location Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Actions

    private func pick(title: String, coordinate: CLLocationCoordinate2D, addToRecents: Bool = true) {
        let alarm = LocationAlarm(
            title: title,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radius: 0, // system default, about 100m
            proximity: proximity
        )
        if addToRecents {
            Self.saveRecent(RecentPlace(title: title, latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        onPick(alarm)
        dismiss()
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        let search = MKLocalSearch(request: request)
        results = (try? await search.start())?.mapItems ?? []
    }

    private func useCurrentLocation() async {
        do {
            let (coordinate, name) = try await locationFetcher.fetch()
            pick(title: name ?? "Current location", coordinate: coordinate)
        } catch {
            currentLocationError = "Couldn't get your location. Check permission in Settings."
        }
    }

    // MARK: - Recents

    struct RecentPlace: Codable {
        var title: String
        var latitude: Double
        var longitude: Double
    }

    private static func loadRecents() -> [RecentPlace] {
        guard let data = UserDefaults.standard.data(forKey: recentsKey),
              let recents = try? JSONDecoder().decode([RecentPlace].self, from: data)
        else { return [] }
        return recents
    }

    private static func saveRecent(_ place: RecentPlace) {
        var recents = loadRecents().filter { $0.title != place.title }
        recents.insert(place, at: 0)
        if let data = try? JSONEncoder().encode(Array(recents.prefix(5))) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }
}

/// One-shot location with When In Use permission, wrapped for async use.
@MainActor
final class CurrentLocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    enum FetchError: Error {
        case denied
        case unavailable
    }

    func fetch() async throws -> (CLLocationCoordinate2D, String?) {
        manager.delegate = self

        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            // The delegate callback re-requests once the user decides.
        }
        guard manager.authorizationStatus != .denied,
              manager.authorizationStatus != .restricted else {
            throw FetchError.denied
        }

        let location = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }

        let name = try? await CLGeocoder()
            .reverseGeocodeLocation(location).first
            .flatMap { $0.name ?? $0.locality }
        return (location.coordinate, name)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let location = locations.first {
                continuation?.resume(returning: location)
                continuation = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
