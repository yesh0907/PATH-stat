import Foundation
import Testing
@testable import PATHKit

@Suite("TrainActivityPlanner")
struct TrainActivityPlannerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let trip = Trip.groveTo33rd
    var endsAt: Date { now.addingTimeInterval(TrainActivityPlanner.defaultDuration) }

    /// A Grove St board with Journal Square–33rd St trains arriving at `offsets` seconds from
    /// `now`, plus a Newark–WTC train (which never stops at 33rd St) at +30 s.
    func snapshot(offsets: [TimeInterval], fetchedAgo: TimeInterval = 0) -> PATHSnapshot {
        let fetchedAt = now.addingTimeInterval(-fetchedAgo)
        func train(_ line: PATHLine, _ offset: TimeInterval) -> TrainArrival {
            TrainArrival(
                station: .groveStreet, direction: .toNY, target: line.stops.last!, headsign: "\(line.displayName)",
                line: line, lineColors: line.colorHex.split(separator: ",").map(String.init), arrival: now.addingTimeInterval(offset),
                arrivalTimeMessage: "", lastUpdated: fetchedAt
            )
        }
        let trains = (offsets.map { train(.journalSquare33rd, $0) } + [train(.newarkWTC, 30)])
            .sorted { $0.arrival < $1.arrival }
        return PATHSnapshot(fetchedAt: fetchedAt, boards: [.groveStreet: [.toNY: trains]])
    }

    func state(_ snapshot: PATHSnapshot?, fetchFailed: Bool = false, at date: Date? = nil, endsAt: Date? = nil) -> TrainActivityState {
        TrainActivityPlanner.state(
            trip: trip, snapshot: snapshot, fetchFailed: fetchFailed, now: date ?? now, endsAt: endsAt ?? self.endsAt
        )
    }

    @Test func keepsOnlyTrainsTowardTheDestination() {
        let result = state(snapshot(offsets: [120, 300]))
        #expect(result.trains.count == 2)
        #expect(result.trains.allSatisfy { $0.line == .journalSquare33rd })
        #expect(result.trains.map(\.arrival) == [now.addingTimeInterval(120), now.addingTimeInterval(300)])
        #expect(result.status == .live)
        #expect(result.fetchedAt == now)
        #expect(result.endsAt == endsAt)
    }

    @Test func dropsDepartedTrains() {
        // Arrived exactly `departedGrace` ago: `departures` keeps it, the activity drops it.
        let grace = DepartureBoard.departedGrace
        let result = state(snapshot(offsets: [-grace, -30, 200]))
        #expect(result.trains.map(\.arrival) == [now.addingTimeInterval(-30), now.addingTimeInterval(200)])
    }

    @Test func capsAtMaxTrains() {
        let result = state(snapshot(offsets: [60, 120, 180, 240, 300, 360]))
        #expect(TrainActivityPlanner.maxTrains == 4)
        #expect(result.trains.count == 4)
        #expect(result.trains.last?.arrival == now.addingTimeInterval(240))
    }

    @Test func sampleSnapshotTowardThirtyThird() {
        let result = state(.sampleTrains(now: now))
        #expect(result.trains.count == 4)
        #expect(result.trains.first?.arrival == now.addingTimeInterval(295))
        #expect(result.trains.allSatisfy { $0.stops(at: .thirtyThirdStreet) })
    }

    @Test func staleAtIsFirstDepartureWhenSoonest() {
        let result = state(snapshot(offsets: [120, 300]))
        #expect(result.staleAt == now.addingTimeInterval(120 + DepartureBoard.departedGrace))
    }

    @Test func staleAtIsCappedByFreshness() {
        let result = state(snapshot(offsets: [900], fetchedAgo: 60))
        #expect(result.staleAt == now.addingTimeInterval(-60 + TrainActivityPlanner.staleAfter))
    }

    @Test func staleAtIsCappedByEndsAt() {
        let end = now.addingTimeInterval(90)
        let result = state(snapshot(offsets: [120]), endsAt: end)
        #expect(result.staleAt == end)
    }

    @Test func staleAtWithoutTrains() {
        let result = state(snapshot(offsets: []))
        #expect(result.trains.isEmpty)
        #expect(result.status == .live)
        #expect(result.staleAt == now.addingTimeInterval(TrainActivityPlanner.staleAfter))

        let end = now.addingTimeInterval(30)
        #expect(state(snapshot(offsets: []), endsAt: end).staleAt == end)
    }

    @Test func nilSnapshotIsOfflineAndStaleNow() {
        let result = state(nil)
        #expect(result.trains.isEmpty)
        #expect(result.fetchedAt == nil)
        #expect(result.status == .offline)
        #expect(result.staleAt == now)
    }

    @Test func staleAtNeverAfterEndsAt() {
        let end = now.addingTimeInterval(-10)
        #expect(state(nil, endsAt: end).staleAt == end)
        #expect(state(snapshot(offsets: [120]), endsAt: end).staleAt == end)
    }

    @Test func fetchFailedIsOfflineWithCachedTrains() {
        let result = state(snapshot(offsets: [120], fetchedAgo: 180), fetchFailed: true)
        #expect(result.status == .offline)
        #expect(result.trains.count == 1)
        #expect(result.fetchedAt == now.addingTimeInterval(-180))
    }

    @Test func endedAtOrAfterEndsAt() {
        #expect(state(snapshot(offsets: [120]), endsAt: now).status == .ended)
        #expect(state(nil, endsAt: now.addingTimeInterval(-1)).status == .ended)
        #expect(state(snapshot(offsets: [120]), fetchFailed: true, endsAt: now).status == .ended)
    }

    // MARK: visibleTrains / showsStaleWarning

    @Test func visibleTrainsWhenNotStale() {
        let result = state(snapshot(offsets: [120, 300]))
        #expect(result.visibleTrains(isStale: false) == result.trains)
    }

    @Test func visibleTrainsRollOverOnceStale() {
        let result = state(snapshot(offsets: [120, 300, 480]))
        // staleAt is the first train's departure: once stale it is dropped.
        let visible = result.visibleTrains(isStale: true)
        #expect(visible.map(\.arrival) == [now.addingTimeInterval(300), now.addingTimeInterval(480)])
    }

    @Test func visibleTrainsKeepLaterTrainsWhenStaleFromAge() {
        let result = state(snapshot(offsets: [900, 1200], fetchedAgo: 60))
        #expect(result.visibleTrains(isStale: true) == result.trains)
    }

    @Test func staleWarning() {
        let live = state(snapshot(offsets: [120]))
        #expect(!live.showsStaleWarning(isStale: false))
        #expect(live.showsStaleWarning(isStale: true))
        #expect(state(snapshot(offsets: [120]), fetchFailed: true).showsStaleWarning(isStale: false))
        #expect(state(snapshot(offsets: [120]), endsAt: now).showsStaleWarning(isStale: false))
        #expect(state(nil).showsStaleWarning(isStale: false))
        let noFetch = TrainActivityState(trains: [], fetchedAt: nil, status: .live, staleAt: now, endsAt: endsAt)
        #expect(noFetch.showsStaleWarning(isStale: false))
    }

    // MARK: nextBackgroundRefresh

    @Test func nextBackgroundRefreshNilWhenEnded() {
        let ended = state(snapshot(offsets: [120]), endsAt: now)
        #expect(TrainActivityPlanner.nextBackgroundRefresh(for: ended, now: now) == nil)
    }

    @Test func nextBackgroundRefreshAtStaleAt() {
        let result = state(snapshot(offsets: [300]))
        #expect(TrainActivityPlanner.nextBackgroundRefresh(for: result, now: now) == result.staleAt)
    }

    @Test func nextBackgroundRefreshIsAtLeastAMinuteAway() {
        let result = state(snapshot(offsets: [-30]))
        #expect(result.staleAt == now.addingTimeInterval(30))
        #expect(TrainActivityPlanner.nextBackgroundRefresh(for: result, now: now) == now.addingTimeInterval(60))
        #expect(TrainActivityPlanner.nextBackgroundRefresh(for: state(nil), now: now) == now.addingTimeInterval(60))
    }

    @Test func stateRoundTripsThroughCodable() throws {
        let result = state(snapshot(offsets: [120, 300]))
        let decoded = try JSONDecoder().decode(TrainActivityState.self, from: JSONEncoder().encode(result))
        #expect(decoded == result)
    }
}

@Suite("SnapshotCache.loadOrFetch")
struct SnapshotCacheLoadOrFetchTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func makeCache() -> SnapshotCache {
        SnapshotCache(directory: FileManager.default.temporaryDirectory
            .appending(path: "loadOrFetch-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    @Test func usesFreshCacheWithoutFetching() async {
        let cache = makeCache()
        cache.save(.sampleTrains(now: now.addingTimeInterval(-30)))
        let result = await cache.loadOrFetch(maxAge: 60, now: now) {
            Issue.record("should not fetch")
            return .sampleTrains(now: now)
        }
        #expect(result.snapshot?.fetchedAt == now.addingTimeInterval(-30))
        #expect(result.error == nil)
    }

    @Test func fetchesAndSavesWhenCacheIsOld() async {
        let cache = makeCache()
        cache.save(.sampleTrains(now: now.addingTimeInterval(-120)))
        let result = await cache.loadOrFetch(maxAge: 60, now: now) { .sampleTrains(now: now) }
        #expect(result.snapshot?.fetchedAt == now)
        #expect(result.error == nil)
        #expect(cache.load()?.fetchedAt == now)
    }

    @Test func fetchesWhenCacheIsFromTheFuture() async {
        let cache = makeCache()
        cache.save(.sampleTrains(now: now.addingTimeInterval(30)))
        let result = await cache.loadOrFetch(maxAge: 60, now: now) { .sampleTrains(now: now) }
        #expect(result.snapshot?.fetchedAt == now)
    }

    @Test func failureReturnsCachedSnapshotAndError() async {
        let cache = makeCache()
        cache.save(.sampleTrains(now: now.addingTimeInterval(-600)))
        let result = await cache.loadOrFetch(maxAge: 60, now: now) { throw URLError(.notConnectedToInternet) }
        #expect(result.snapshot?.fetchedAt == now.addingTimeInterval(-600))
        #expect(result.error == .offline)
        #expect(cache.load()?.fetchedAt == now.addingTimeInterval(-600))
    }

    @Test func failureWithoutCache() async {
        let cache = makeCache()
        let result = await cache.loadOrFetch(maxAge: 60, now: now) { throw URLError(.timedOut) }
        #expect(result.snapshot?.fetchedAt == nil)
        #expect(result.error == .timedOut)
        #expect(cache.load()?.fetchedAt == nil)
    }
}
