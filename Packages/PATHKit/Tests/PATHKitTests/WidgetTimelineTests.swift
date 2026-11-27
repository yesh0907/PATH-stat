import Foundation
import Testing
@testable import PATHKit

@Suite("WidgetTimeline")
struct WidgetTimelineTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let grace = DepartureBoard.departedGrace
    let trip = Trip.groveTo33rd

    /// Grove St ToNY trains on Journal Square–33rd St arriving `offsets` seconds after `now`.
    func snapshot(_ offsets: [TimeInterval], fetchedAgo: TimeInterval = 0) -> PATHSnapshot {
        let trains = offsets.map { offset in
            TrainArrival(
                station: .groveStreet, direction: .toNY, target: .thirtyThirdStreet, headsign: "33rd Street",
                line: .journalSquare33rd, lineColors: ["FF9900"], arrival: now.addingTimeInterval(offset),
                arrivalTimeMessage: "", lastUpdated: now.addingTimeInterval(-fetchedAgo)
            )
        }
        return PATHSnapshot(fetchedAt: now.addingTimeInterval(-fetchedAgo), boards: [.groveStreet: [.toNY: trains]])
    }

    func entry(at offset: TimeInterval, in entries: [WidgetEntryState]) -> WidgetEntryState? {
        entries.first { $0.date == now.addingTimeInterval(offset) }
    }

    @Test func rollsToNextTrainAfterDeparture() throws {
        let result = WidgetTimeline.make(trip: trip, snapshot: snapshot([120, 420]), fetchFailed: false, now: now)
        let first = try #require(entry(at: 0, in: result.entries))
        #expect(first.trains.map(\.arrival) == [now.addingTimeInterval(120), now.addingTimeInterval(420)])
        // At arrival the train is still listed (within the departed grace).
        #expect(entry(at: 120, in: result.entries)?.trains.count == 2)
        let afterFirst = try #require(entry(at: 120 + grace, in: result.entries))
        #expect(afterFirst.trains.map(\.arrival) == [now.addingTimeInterval(420)])
        #expect(entry(at: 420 + grace, in: result.entries)?.trains.isEmpty == true)
    }

    @Test func entryDatesAreExactSortedAndNotBeforeNow() {
        // One train already arrived 30 s ago (still within grace); its arrival date is < now.
        let result = WidgetTimeline.make(trip: trip, snapshot: snapshot([-30, 120], fetchedAgo: 60), fetchFailed: false, now: now)
        let offsets = result.entries.map { $0.date.timeIntervalSince(now) }
        #expect(offsets == [0, -30 + grace, 120, 120 + grace, WidgetTimeline.staleAfter - 60])
        #expect(result.entries.allSatisfy { $0.date >= now })
        #expect(Set(result.entries.map(\.date)).count == result.entries.count)
    }

    @Test func departedTrainsBeforeNowAreExcluded() {
        let result = WidgetTimeline.make(trip: trip, snapshot: snapshot([-300, 120]), fetchFailed: false, now: now)
        #expect(result.entries[0].trains.map(\.arrival) == [now.addingTimeInterval(120)])
    }

    @Test func capsAtMaxTrains() {
        let offsets: [TimeInterval] = [60, 180, 300, 420, 540]
        let result = WidgetTimeline.make(trip: trip, snapshot: snapshot(offsets), fetchFailed: false, now: now)
        #expect(result.entries[0].trains.count == 3)
        let two = WidgetTimeline.make(trip: trip, snapshot: snapshot(offsets), fetchFailed: false, now: now, maxTrains: 2)
        #expect(two.entries[0].trains.map(\.arrival) == [now.addingTimeInterval(60), now.addingTimeInterval(180)])
        // Entries still cover the trains beyond the cap.
        #expect(entry(at: 540 + grace, in: two.entries) != nil)
    }

    @Test func staleEntryAppears() throws {
        let result = WidgetTimeline.make(trip: trip, snapshot: snapshot([60, 900], fetchedAgo: 120), fetchFailed: false, now: now)
        let staleAt = WidgetTimeline.staleAfter - 120
        #expect(result.entries.filter { $0.date.timeIntervalSince(now) < staleAt }.allSatisfy { $0.status == .live })
        let stale = try #require(entry(at: staleAt, in: result.entries))
        #expect(stale.status == .stale)
        #expect(result.entries.filter { $0.date.timeIntervalSince(now) >= staleAt }.allSatisfy { $0.status == .stale })
        #expect(stale.fetchedAt == now.addingTimeInterval(-120))
    }

    @Test func alreadyStaleSnapshotIsStaleFromNow() {
        let result = WidgetTimeline.make(trip: trip, snapshot: snapshot([60], fetchedAgo: 3600), fetchFailed: false, now: now)
        #expect(result.entries.first?.date == now)
        #expect(result.entries.allSatisfy { $0.status == .stale })
    }

    @Test func offlineStatusWhenFetchFailed() {
        let result = WidgetTimeline.make(trip: trip, snapshot: snapshot([60, 300]), fetchFailed: true, now: now)
        #expect(result.entries.allSatisfy { $0.status == .offline })
        #expect(result.entries[0].trains.count == 2)
        #expect(result.reloadAt == now.addingTimeInterval(WidgetTimeline.retryInterval))
    }

    @Test func unavailableWithoutSnapshot() {
        let result = WidgetTimeline.make(trip: trip, snapshot: nil, fetchFailed: true, now: now)
        #expect(result.entries == [
            WidgetEntryState(date: now, trip: trip, trains: [], fetchedAt: nil, status: .unavailable),
        ])
        #expect(result.reloadAt == now.addingTimeInterval(WidgetTimeline.retryInterval))
        #expect(WidgetTimeline.make(trip: trip, snapshot: nil, fetchFailed: false, now: now).entries[0].status == .unavailable)
    }

    @Test func filtersByTrip() {
        // A WTC-bound train at Grove St doesn't stop at 33rd St.
        let wtc = TrainArrival(
            station: .groveStreet, direction: .toNY, target: .worldTradeCenter, headsign: "World Trade Center",
            line: .newarkWTC, lineColors: ["D93A30"], arrival: now.addingTimeInterval(60),
            arrivalTimeMessage: "", lastUpdated: now
        )
        let snap = PATHSnapshot(fetchedAt: now, boards: [.groveStreet: [.toNY: [wtc]]])
        #expect(WidgetTimeline.make(trip: trip, snapshot: snap, fetchFailed: false, now: now).entries[0].trains.isEmpty)
        #expect(WidgetTimeline.make(trip: .groveToWTC, snapshot: snap, fetchFailed: false, now: now).entries[0].trains == [wtc])
    }

    // MARK: reloadAt

    @Test func reloadIdleWithoutUpcomingTrains() {
        let result = WidgetTimeline.make(trip: trip, snapshot: snapshot([]), fetchFailed: false, now: now)
        #expect(result.reloadAt == now.addingTimeInterval(WidgetTimeline.idleInterval))
        #expect(result.entries[0].trains.isEmpty)
        #expect(result.entries[0].status == .live)
    }

    @Test func reloadAtRefreshIntervalWhenTrainsOutlastIt() {
        let result = WidgetTimeline.make(trip: trip, snapshot: snapshot([60, 1800]), fetchFailed: false, now: now)
        #expect(result.reloadAt == now.addingTimeInterval(WidgetTimeline.refreshInterval))
    }

    @Test func reloadWhenLastTrainDeparts() {
        let result = WidgetTimeline.make(trip: trip, snapshot: snapshot([60, 480]), fetchFailed: false, now: now)
        #expect(result.reloadAt == now.addingTimeInterval(480 + grace))
    }

    @Test func reloadNoEarlierThanRetryInterval() {
        let result = WidgetTimeline.make(trip: trip, snapshot: snapshot([30]), fetchFailed: false, now: now)
        #expect(result.reloadAt == now.addingTimeInterval(WidgetTimeline.retryInterval))
    }
}

@Suite("ReloadThrottle")
struct ReloadThrottleTests {
    @Test func allowsFirstThenOncePerInterval() {
        let start = Date(timeIntervalSince1970: 1_000)
        var throttle = ReloadThrottle(minInterval: 60)
        // Offsets from `start`; measured from the last allowed reload, not the last call.
        let results = [0, 0, 59, 60, 100, 120].map { throttle.shouldReload(at: start.addingTimeInterval(TimeInterval($0))) }
        #expect(results == [true, false, false, true, false, true])
    }
}

@Suite("WidgetTripResolver")
struct WidgetTripResolverTests {
    @Test func savedTrip() {
        #expect(WidgetTripResolver.resolve(.savedTrip(.goingHome), location: nil).trip == .goingHome)
        let none = WidgetTripResolver.resolve(.savedTrip(nil), location: nil)
        #expect(none == .init(trip: .groveTo33rd, locationUnavailable: false))
    }

    @Test func customRoute() {
        #expect(WidgetTripResolver.resolve(.custom(from: .hoboken, to: .worldTradeCenter), location: nil).trip
            == Trip(origin: .hoboken, destination: .worldTradeCenter))
        // Matches a preset → keeps its name.
        #expect(WidgetTripResolver.resolve(.custom(from: .twentyThirdStreet, to: .groveStreet), location: nil).trip == .goingHome)
    }

    @Test func customUnservedFallsBack() {
        for choice in [
            WidgetTripChoice.custom(from: .hoboken, to: .newark),
            .custom(from: .groveStreet, to: .groveStreet),
            .custom(from: nil, to: .groveStreet),
            .custom(from: .groveStreet, to: nil),
        ] {
            #expect(WidgetTripResolver.resolve(choice, location: nil) == .init(trip: .groveTo33rd))
        }
    }

    @Test func nearest() {
        let none = WidgetTripResolver.resolve(.nearest, location: nil, lastTrip: .groveToWTC)
        #expect(none == .init(trip: .groveTo33rd, locationUnavailable: true))
        let near23rd = WidgetTripResolver.resolve(.nearest, location: StationCatalog.station(.twentyThirdStreet).location)
        #expect(near23rd == .init(trip: .goingHome, locationUnavailable: false))
    }
}
