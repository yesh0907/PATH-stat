import CoreLocation
import Foundation
import Observation
import os
import PATHKit

/// When-in-use location for picking the nearest station. Never runs in the background.
///
/// In scenario mode (UI tests, previews) the service is created with fixed state via
/// `LocationService.fixed(...)` and never touches `CLLocationManager`.
@MainActor
@Observable
final class LocationService {
    typealias Authorization = LocationAuthorization

    private(set) var authorization: Authorization
    private(set) var location: CLLocation?

    @ObservationIgnored private let isLive: Bool
    @ObservationIgnored private var manager: CLLocationManager?
    @ObservationIgnored private var delegate: Delegate?
    @ObservationIgnored private let logger = Logger(subsystem: "com.yesh0907.PATHStat", category: "location")

    init() {
        isLive = true
        authorization = .notDetermined
    }

    private init(authorization: Authorization, location: CLLocation?) {
        isLive = false
        self.authorization = authorization
        self.location = location
    }

    /// A service with fixed state, for UI-test scenarios and previews.
    static func fixed(authorization: Authorization, location: CLLocation?) -> LocationService {
        LocationService(authorization: authorization, location: location)
    }

    /// Creates the manager (once). CoreLocation then calls `locationManagerDidChangeAuthorization`,
    /// which asks for when-in-use permission if needed and requests a fix.
    func start() {
        guard isLive else { return }
        if manager == nil {
            let manager = CLLocationManager()
            let delegate = Delegate(owner: self)
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            // Store both before setting the delegate: CoreLocation may call
            // `locationManagerDidChangeAuthorization` immediately, and that guards on `self.manager`.
            self.manager = manager
            self.delegate = delegate
            manager.delegate = delegate
        }
    }

    /// Requests a fresh one-shot fix (e.g. on returning to the foreground).
    func refresh() {
        guard isLive, authorization == .authorized else { return }
        manager?.requestLocation()
    }

    fileprivate func handleAuthorizationChange() {
        guard let manager else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            authorization = .notDetermined
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            authorization = .authorized
            manager.requestLocation()
        case .denied, .restricted:
            authorization = .denied
            location = nil
        @unknown default:
            authorization = .denied
            location = nil
        }
    }

    fileprivate func handle(_ location: CLLocation) {
        self.location = location
    }

    fileprivate func handleFailure(code: Int) {
        // Only the error code: never coordinates or anything location-derived.
        logger.notice("Location request failed: \(code, privacy: .public)")
    }

    /// Bridges `CLLocationManagerDelegate` callbacks (delivered on the main thread, where the
    /// manager was created) onto the main actor.
    private final class Delegate: NSObject, CLLocationManagerDelegate {
        private weak var owner: LocationService?

        init(owner: LocationService) {
            self.owner = owner
        }

        nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            let owner = owner
            MainActor.assumeIsolated { owner?.handleAuthorizationChange() }
        }

        nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let location = locations.last else { return }
            let owner = owner
            MainActor.assumeIsolated { owner?.handle(location) }
        }

        nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
            let code = (error as NSError).code
            let owner = owner
            MainActor.assumeIsolated { owner?.handleFailure(code: code) }
        }
    }
}
