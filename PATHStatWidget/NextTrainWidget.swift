import os
import PATHKit
import SwiftUI
import WidgetKit

struct NextTrainEntry: TimelineEntry {
    let state: WidgetEntryState
    /// "Nearest station" was configured but no location fix was available.
    var locationUnavailable = false

    var date: Date { state.date }
}

struct NextTrainProvider: AppIntentTimelineProvider {
    /// A cached snapshot younger than this is used as-is instead of fetching.
    static let cacheFreshness: TimeInterval = 60

    private static let logger = Logger(subsystem: "com.yesh0907.PATHStat", category: "feed")

    func placeholder(in context: Context) -> NextTrainEntry {
        NextTrainEntry(state: WidgetSampleState.live.entry(now: .now))
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> NextTrainEntry {
        // Gallery / quick snapshot: sample data, no location or network.
        let trip = WidgetTripResolver.resolve(configuration.choice, location: nil, lastTrip: TripStore.shared.lastTrip).trip
        let now = Date.now
        let state = WidgetTimeline.make(trip: trip, snapshot: .sampleTrains(now: now), fetchFailed: false, now: now).entries[0]
        return NextTrainEntry(state: state)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<NextTrainEntry> {
        let location = configuration.mode == .nearest ? await OneShotLocation.current() : nil
        let resolution = WidgetTripResolver.resolve(configuration.choice, location: location, lastTrip: TripStore.shared.lastTrip)

        let (snapshot, fetchFailed) = await Self.loadSnapshot()
        let now = Date.now
        let timeline = WidgetTimeline.make(trip: resolution.trip, snapshot: snapshot, fetchFailed: fetchFailed, now: now)
        let entries = timeline.entries.map { NextTrainEntry(state: $0, locationUnavailable: resolution.locationUnavailable) }
        return Timeline(entries: entries, policy: .after(timeline.reloadAt))
    }

    /// The cached snapshot if it is under a minute old, else a fresh fetch (cached on success).
    /// On failure: the cached snapshot (possibly nil) with `fetchFailed`.
    private static func loadSnapshot() async -> (PATHSnapshot?, Bool) {
        let cache = SnapshotCache.shared
        let cached = cache.load()
        if let cached {
            let age = Date.now.timeIntervalSince(cached.fetchedAt)
            if age >= 0, age < cacheFreshness { return (cached, false) }
        }
        do {
            let snapshot = try await PATHClient().fetchSnapshot()
            cache.save(snapshot)
            return (snapshot, false)
        } catch {
            let pathError = PATHError.from(error)
            logger.error("Widget feed fetch failed: \(String(describing: pathError), privacy: .public)")
            return (cached, true)
        }
    }
}

struct NextTrainWidgetEntryView: View {
    let entry: NextTrainEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        NextTrainWidgetView(state: entry.state, family: family, locationUnavailable: entry.locationUnavailable)
            .widgetURL(entry.state.trip.url)
            .containerBackground(for: .widget) {
                switch family {
                case .accessoryCircular, .accessoryRectangular, .accessoryInline:
                    AccessoryWidgetBackground()
                default:
                    Color(.systemBackground)
                }
            }
    }
}

struct NextTrainWidget: Widget {
    static let kind = "NextTrainWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: ConfigurationAppIntent.self, provider: NextTrainProvider()) { entry in
            NextTrainWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Next PATH train")
        .description("Live countdowns to the next PATH trains for a saved trip, any station, or the nearest station.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

@main
struct PATHStatWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextTrainWidget()
    }
}

// MARK: - Previews

private func previewEntries(_ states: [WidgetSampleState] = WidgetSampleState.allCases) -> [NextTrainEntry] {
    let now = Date.now
    return states.map { NextTrainEntry(state: $0.entry(now: now)) }
}

#Preview("Small", as: .systemSmall) {
    NextTrainWidget()
} timeline: {
    for entry in previewEntries() { entry }
}

#Preview("Medium", as: .systemMedium) {
    NextTrainWidget()
} timeline: {
    for entry in previewEntries() { entry }
}

#Preview("Rectangular", as: .accessoryRectangular) {
    NextTrainWidget()
} timeline: {
    for entry in previewEntries() { entry }
}

#Preview("Inline", as: .accessoryInline) {
    NextTrainWidget()
} timeline: {
    for entry in previewEntries() { entry }
}

#Preview("Circular", as: .accessoryCircular) {
    NextTrainWidget()
} timeline: {
    for entry in previewEntries() { entry }
}
