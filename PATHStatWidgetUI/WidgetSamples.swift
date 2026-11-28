import Foundation
import PATHKit

/// Fixed widget states built with `WidgetTimeline.make` from PATHKit's sample snapshots, for
/// the app's `-WidgetGallery` mode, widget previews and placeholders.
enum WidgetSampleState: String, CaseIterable, Sendable {
    case live
    case due
    case stale
    case offline
    case unavailable
    case noTrains

    /// Age of the sample snapshot's `fetchedAt` at `now`.
    var fetchedAgo: TimeInterval {
        switch self {
        case .live, .due, .noTrains, .unavailable: 4
        case .stale: 14 * 60
        case .offline: 3 * 60
        }
    }

    /// The timeline `WidgetTimeline.make` builds for this state at `now`.
    func timeline(trip: Trip = .groveTo33rd, now: Date) -> (entries: [WidgetEntryState], reloadAt: Date) {
        let snapshot: PATHSnapshot?
        switch self {
        case .unavailable:
            snapshot = nil
        case .noTrains:
            snapshot = .sampleNoTrains(now: now)
        case .live, .due, .stale, .offline:
            // Upcoming trains relative to `now`, but fetched `fetchedAgo` earlier.
            snapshot = PATHSnapshot(fetchedAt: now.addingTimeInterval(-fetchedAgo), boards: PATHSnapshot.sampleTrains(now: now).boards)
        }
        return WidgetTimeline.make(trip: trip, snapshot: snapshot, fetchFailed: self == .offline || self == .unavailable, now: now)
    }

    /// The first entry of `timeline(trip:now:)` — except `.due`, which picks the first entry
    /// whose next train's countdown is `.due` (falling back to the first entry).
    func entry(trip: Trip = .groveTo33rd, now: Date) -> WidgetEntryState {
        let entries = timeline(trip: trip, now: now).entries
        if self == .due,
           let due = entries.first(where: { entry in
               entry.trains.first.map { entry.countdown(for: $0) == .due } ?? false
           }) {
            return due
        }
        return entries[0]
    }
}
