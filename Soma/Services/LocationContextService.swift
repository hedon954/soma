import CoreLocation
import Foundation
import MapKit
import Observation

struct LocationSnapshot: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var capturedAt: Date
    var placeName: String?

    var displayName: String {
        placeName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "已记录位置"
    }
}

enum GymContextSource: String, Equatable, Sendable {
    case explicit
    case nearby
    case current
    case none
}

struct GymContextResolution: Equatable, Sendable {
    var gymID: UUID?
    var source: GymContextSource
}

enum GymLocationResolver {
    static let maximumUsableAccuracy = 250.0

    static func resolve(
        text: String,
        snapshot: LocationSnapshot?,
        gyms: [GymProfile]
    ) -> GymContextResolution {
        if let explicit = explicitlyNamedGym(in: text, gyms: gyms) {
            return GymContextResolution(gymID: explicit.id, source: .explicit)
        }
        if let nearby = uniqueNearbyGym(for: snapshot, gyms: gyms) {
            return GymContextResolution(gymID: nearby.id, source: .nearby)
        }
        if let current = GymSelection.current(in: gyms) {
            return GymContextResolution(gymID: current.id, source: .current)
        }
        return GymContextResolution(gymID: nil, source: .none)
    }

    static func uniqueNearbyGym(
        for snapshot: LocationSnapshot?,
        gyms: [GymProfile]
    ) -> GymProfile? {
        guard let snapshot,
              snapshot.horizontalAccuracy >= 0,
              snapshot.horizontalAccuracy <= maximumUsableAccuracy
        else {
            return nil
        }

        let candidates = gyms.filter { gym in
            guard let latitude = gym.latitude, let longitude = gym.longitude else {
                return false
            }
            let distance = distanceMeters(
                fromLatitude: snapshot.latitude,
                longitude: snapshot.longitude,
                toLatitude: latitude,
                longitude: longitude
            )
            return distance <= max(gym.matchRadiusMeters, snapshot.horizontalAccuracy)
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    static func distanceMeters(
        fromLatitude: Double,
        longitude fromLongitude: Double,
        toLatitude: Double,
        longitude toLongitude: Double
    ) -> Double {
        let radius = 6_371_000.0
        let latitudeDelta = (toLatitude - fromLatitude) * .pi / 180
        let longitudeDelta = (toLongitude - fromLongitude) * .pi / 180
        let firstLatitude = fromLatitude * .pi / 180
        let secondLatitude = toLatitude * .pi / 180
        let haversineComponent = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(firstLatitude) * cos(secondLatitude)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return radius * 2 * atan2(
            sqrt(haversineComponent),
            sqrt(1 - haversineComponent)
        )
    }

    private static func explicitlyNamedGym(
        in text: String,
        gyms: [GymProfile]
    ) -> GymProfile? {
        let normalized = normalizedText(text)
        let matches = gyms.filter {
            let name = normalizedText($0.name)
            return !name.isEmpty && normalized.contains(name)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }
}

@MainActor
@Observable
final class LocationContextService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var isRequesting = false

    @ObservationIgnored
    private let manager = CLLocationManager()
    @ObservationIgnored
    private var continuation: CheckedContinuation<LocationSnapshot?, Never>?
    @ObservationIgnored
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestSnapshot() async -> LocationSnapshot? {
        guard CLLocationManager.locationServicesEnabled(), continuation == nil else {
            return nil
        }

        isRequesting = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled else { return }
                self?.finish(nil)
            }
            startRequestForCurrentAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        startRequestForCurrentAuthorization()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard continuation != nil else { return }
        let now = Date()
        guard let location = locations
            .filter({
                $0.horizontalAccuracy >= 0
                    && $0.horizontalAccuracy <= 1000
                    && abs($0.timestamp.timeIntervalSince(now)) <= 60
            })
            .min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy })
        else {
            finish(nil)
            return
        }

        timeoutTask?.cancel()
        timeoutTask = nil
        Task { @MainActor [weak self] in
            let placeName = await Self.reverseGeocode(location)
            self?.finish(LocationSnapshot(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracy: location.horizontalAccuracy,
                capturedAt: location.timestamp,
                placeName: placeName
            ))
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        finish(nil)
    }

    private func startRequestForCurrentAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(nil)
        @unknown default:
            finish(nil)
        }
    }

    private func finish(_ snapshot: LocationSnapshot?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        manager.stopUpdatingLocation()
        isRequesting = false
        let pending = continuation
        continuation = nil
        pending?.resume(returning: snapshot)
    }

    private static func reverseGeocode(_ location: CLLocation) async -> String? {
        if #available(iOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let mapItem = try? await request.mapItems.first
            else {
                return nil
            }
            return mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        return await legacyReverseGeocode(location)
    }

    @available(iOS, introduced: 5.0, obsoleted: 26.0)
    private static func legacyReverseGeocode(_ location: CLLocation) async -> String? {
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return nil
        }
        return [
            placemark.name,
            placemark.subLocality,
            placemark.locality
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        .removingDuplicates()
        .prefix(2)
        .joined(separator: " · ")
        .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
