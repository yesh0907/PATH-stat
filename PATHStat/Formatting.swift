import CoreLocation
import Foundation
import PATHKit

/// Display strings shared by the main screen and its accessibility labels.
enum Format {
    /// "4:07", or "Due" when the train is at (or past) the platform.
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        guard total > 0 else { return "Due" }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "4 minutes, 12 seconds" / "now", for VoiceOver.
    static func spokenCountdown(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        guard total > 0 else { return "now" }
        return "in " + Duration.seconds(total).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }

    /// "8:42 PM".
    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "0.3 mi" (or the locale's road unit); `wide` gives "0.3 miles".
    static func distance(_ meters: CLLocationDistance, wide: Bool = false) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: wide ? .wide : .abbreviated, usage: .road))
    }

    /// "12 s" / "3 min".
    static func age(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return total < 60 ? "\(total) s" : "\(total / 60) min"
    }

    static func minutes(_ train: TrainArrival, at now: Date) -> String {
        let minutes = train.minutesRemaining(at: now)
        return minutes == 0 ? "Due" : "\(minutes) min"
    }
}
