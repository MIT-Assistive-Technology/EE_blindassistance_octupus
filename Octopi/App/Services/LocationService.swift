import CoreLocation
import Foundation
import OctopiCore

/// Wraps CoreLocation and delivers `GeoFix`es on the main actor.
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    var onFix: ((GeoFix) -> Void)?
    var onAuthorizationChange: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 2
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
    }

    var authorizationDescription: String {
        switch authorization {
        case .authorizedAlways: "Allowed always"
        case .authorizedWhenInUse: "Allowed while using"
        case .denied: "Denied. Turn it on in Settings."
        case .restricted: "Restricted"
        case .notDetermined: "Not asked yet"
        @unknown default: "Unknown"
        }
    }

    var isAuthorized: Bool { authorization == .authorizedAlways || authorization == .authorizedWhenInUse }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        guard isAuthorized else { return }
        if authorization == .authorizedAlways { manager.allowsBackgroundLocationUpdates = true }
        manager.startUpdatingLocation()
    }

    func stop() { manager.stopUpdatingLocation() }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            self.onAuthorizationChange?()
            self.start()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.map { location in
            GeoFix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                   horizontalAccuracy: location.horizontalAccuracy, timestamp: location.timestamp,
                   speed: location.speed >= 0 ? location.speed : nil,
                   course: location.course >= 0 ? location.course : nil)
        }
        Task { @MainActor in
            for fix in fixes { self.onFix?(fix) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
