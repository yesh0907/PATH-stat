import CoreLocation
import os

/// One location fix for the widget's "Nearest station" mode: `requestLocation()` at 100 m
/// accuracy, only when already authorized, with a timeout. Never logs coordinates.
@MainActor
final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.yesh0907.PATHStat", category: "location")

    /// A fresh fix, or nil if not authorized, failed, or nothing arrived within `timeout`.
    static func current(timeout: Duration = .seconds(5)) async -> CLLocation? {
        await OneShotLocation().run(timeout: timeout)
    }

    private func run(timeout: Duration) async -> CLLocation? {
        guard manager.isAuthorizedForWidgetUpdates else { return nil }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: break
        default: return nil
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
            timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: timeout)
                self.finish(nil)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation else { return }
        self.continuation = nil
        manager.delegate = nil
        continuation.resume(returning: location)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.finish(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let code = (error as NSError).code
        Task { @MainActor in
            // Only the error code: never coordinates or anything location-derived.
            self.logger.notice("Widget location request failed: \(code, privacy: .public)")
            self.finish(nil)
        }
    }
}
