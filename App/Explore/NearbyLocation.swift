import Foundation
import CoreLocation
import Observation

struct SearchLocation: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

/// A one-shot foreground location request. Constructing this helper never asks for permission.
@MainActor @Observable final class NearbyLocation: NSObject, CLLocationManagerDelegate {
    var location: SearchLocation?
    var isRequesting = false
    var errorMessage: String?
    var shouldOfferSettings = false
    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        guard !isRequesting else { return }
        location = nil
        errorMessage = nil
        shouldOfferSettings = false
        isRequesting = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: permissionDenied()
        @unknown default:
            isRequesting = false
            errorMessage = "Location isn’t available. You can still search by address or town."
        }
    }

    /// Ignore a late one-shot result when the person starts a different search or leaves Explore.
    func cancel(clearLocation: Bool = false) {
        isRequesting = false
        manager.stopUpdatingLocation()
        if clearLocation { location = nil }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, self.isRequesting else { return }
            switch self.manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse: self.manager.requestLocation()
            case .denied, .restricted: self.permissionDenied()
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let coordinate = SearchLocation(latitude: latest.coordinate.latitude, longitude: latest.coordinate.longitude)
        let accuracy = latest.horizontalAccuracy
        Task { @MainActor [weak self] in
            guard let self, self.isRequesting else { return }
            self.isRequesting = false
            guard accuracy >= 0 else {
                self.errorMessage = "A reliable location couldn’t be found. Try again or search a town."
                return
            }
            // A broad coverage check, not a representation of New Jersey’s exact border.
            guard (38.9...41.4).contains(coordinate.latitude), (-75.6 ... -73.8).contains(coordinate.longitude) else {
                self.errorMessage = "Watchdog currently searches New Jersey property records. Enter a New Jersey address or town to explore."
                return
            }
            self.location = coordinate
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.isRequesting else { return }
            self.isRequesting = false
            self.errorMessage = "Your location couldn’t be found. Please try again, or search by address or town."
        }
    }

    private func permissionDenied() {
        isRequesting = false
        shouldOfferSettings = manager.authorizationStatus == .denied
        errorMessage = "Location access is off. You can enable it in Settings, or keep searching by address, town, or the map."
    }
}
