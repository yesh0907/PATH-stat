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
        // Minute boundaries of the 120 s train (60, 0) join the original dates. The staleAt
        // entry is dropped: once every train has departed, it is visually identical to the
        // previous empty stale entry.
        #expect(offsets == [0, -30 + grace, 60, 120, 120 + grace])
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
        #expect(result.entries.filter { !$0.trains.isEmpty }.allSatisfy { $0.status == .offline })
        #expect(result.entries.filter { $0.trains.isEmpty }.allSatisfy { $0.status == .unavailable })
        #expect(result.entries[0].trains.count == 2)
        #expect(result.reloadAt == now.addingTimeInterval(WidgetTimeline.retryInterval))
    }

    @Test func offlineSnapshotAllDepartedIsUnavailable() {
        let result = WidgetTimeline.make(trip: trip, snapshot: snapshot([-600]), fetchFailed: true, now: now)
        #expect(!result.entries.isEmpty)
        #expect(result.entries.allSatisfy { $0.status == .unavailable && $0.trains.isEmpty })
        #expect(result.entries.allSatisfy { $0.fetchedAt != nil })
    }

    @Test func offlineTurnsUnavailableOnceLastTrainDeparts() throws {
        let result = WidgetTimeline.make(trip: trip, snapshot: snapshot([120]), fetchFailed: true, now: now)
        let first = try #require(entry(at: 0, in: result.entries))
        #expect(first.status == .offline)
        #expect(first.trains.count == 1)
        let tail = try #require(entry(at: 120 + grace, in: result.entries))
        #expect(tail.status == .unavailable)
        #expect(tail.trains.isEmpty)
    }

    @Test func liveTailEntryWithoutTrainsIsStale() throws {
        let result = WidgetTimeline.make(trip: trip, snapshot: snapshot([120]), fetchFailed: false, now: now)
        let tail = try #require(entry(at: 120 + grace, in: result.entries))
        #expect(tail.trains.isEmpty)
        #expect(tail.status == .stale)
    }

    @Test func originallyEmptyLiveSnapshotStaysLive() {
        let result = WidgetTimeline.make(trip: trip, snapshot: snapshot([]), fetchFailed: false, now: now)
        #expect(result.entries.allSatisfy { $0.status == .live || $0.date >= now.addingTimeInterval(WidgetTimeline.staleAfter) })
        let first = result.entries.first
        #expect(first?.trains.isEmpty == true)
        #expect(first?.status == .live)
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


    // MARK: minute-boundary countdowns

    @Test func countdownRounding() {
        let arrival = now.addingTimeInterval(1_000)
        func check(_ remaining: TimeInterval, _ expected: MinutesCountdown) {
            #expect(WidgetTimeline.countdown(to: now.addingTimeInterval(remaining), at: now) == expected)
            _ = arrival
        }
        check(299, .minutes(4))
        check(300, .minutes(4))
        check(300.5, .minutes(5))
        check(61, .minutes(1))
        check(60, .due)
        check(1, .due)
        check(0, .now)
        check(-10, .now)
        #expect(MinutesCountdown.minutes(4).text == "in 4 min")
        #expect(MinutesCountdown.due.text == "due")
        #expect(MinutesCountdown.now.text == "now")
        #expect(MinutesCountdown.minutes(4).compactText == "4m")
        #expect(MinutesCountdown.due.compactText == "due")
        #expect(MinutesCountdown.now.compactText == "now")
    }

    @Test func minuteBoundaryEntriesTickTheCountdownDown() throws {
        let result = WidgetTimeline.make(trip: trip, snapshot: snapshot([300.5]), fetchFailed: false, now: now)
        for offset in [0.5, 60.5, 120.5, 180.5, 240.5] {
            #expect(entry(at: offset, in: result.entries) != nil, "missing entry at \(offset)")
        }
        // The first train's countdown over consecutive entries before its departure.
        func rank(_ countdown: MinutesCountdown) -> Int {
            switch countdown {
            case .minutes(let minutes): minutes + 1
            case .due: 1
            case .now: 0
            }
        }
        var sequence: [Int] = []
        for entry in result.entries {
            guard let train = entry.trains.first, train.arrival == now.addingTimeInterval(300.5) else { continue }
            if train.arrival.addingTimeInterval(grace) <= entry.date { continue }
            let value = rank(entry.countdown(for: train))
            if sequence.last != value { sequence.append(value) }
        }
        #expect(sequence == [6, 5, 4, 3, 2, 1, 0])  // minutes(5)…minutes(1), due, now
    }

    @Test func noTwoConsecutiveEntriesAreVisuallyEqual() {
        let result = WidgetTimeline.make(trip: trip, snapshot: snapshot([150, 400]), fetchFailed: false, now: now)
        for (previous, next) in zip(result.entries, result.entries.dropFirst()) {
            let same = previous.status == next.status
                && previous.trains == next.trains
                && zip(previous.trains, next.trains).allSatisfy { previous.countdown(for: $0) == next.countdown(for: $1) }
            #expect(!same, "entries at \(previous.date) and \(next.date) are visually identical")
        }
    }

    @Test func secondTrainBoundariesAppear() {
        let result = WidgetTimeline.make(trip: trip, snapshot: snapshot([150, 400]), fetchFailed: false, now: now)
        for k in 1...6 {
            #expect(entry(at: 400 - TimeInterval(k) * 60, in: result.entries) != nil, "missing boundary 400-\(k)*60")
        }
    }

    @Test func countdownIsValidForEachEntrysWholeSpan() {
        let result = WidgetTimeline.make(trip: trip, snapshot: snapshot([37, 95, 412, 777], fetchedAgo: 30), fetchFailed: false, now: now)
        for (index, entry) in result.entries.enumerated() {
            let spanEnd = index + 1 < result.entries.count
                ? result.entries[index + 1].date.addingTimeInterval(-0.001)
                : entry.date
            for train in entry.trains {
                let atStart = entry.countdown(for: train)
                #expect(atStart == WidgetTimeline.countdown(to: train.arrival, at: entry.date))
                #expect(atStart == WidgetTimeline.countdown(to: train.arrival, at: spanEnd),
                        "countdown of train at \(train.arrival) changes within the span starting \(entry.date)")
            }
        }
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

    @Test func smart() {
        let none = WidgetTripResolver.resolve(.smart, location: nil)
        #expect(none == .init(trip: .groveTo33rd, locationUnavailable: true))

        let near23rd = WidgetTripResolver.resolve(.smart, location: StationCatalog.station(.twentyThirdStreet).location)
        #expect(near23rd == .init(trip: .goingHome, nearestStation: .twentyThirdStreet))

        let nearGrove = WidgetTripResolver.resolve(.smart, location: StationCatalog.station(.groveStreet).location)
        #expect(nearGrove.trip == .groveTo33rd)
        #expect(nearGrove.locationUnavailable == false)
        #expect(nearGrove.nearestStation == .groveStreet)

        // No fix, but the app remembered a nearest station: smart trip for it, not unavailable.
        let stored = WidgetTripResolver.resolve(.smart, location: nil, lastNearestStation: .hoboken)
        #expect(stored == .init(trip: Trip(origin: .hoboken, destination: .groveStreet)))
        // A fresh fix wins over the stored one.
        let fresh = WidgetTripResolver.resolve(
            .smart,
            location: StationCatalog.station(.twentyThirdStreet).location,
            lastNearestStation: .hoboken
        )
        #expect(fresh.trip == .goingHome)
    }
}
