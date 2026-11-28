import CoreLocation
import Foundation
import Testing
@testable import PATHKit

@MainActor
@Suite("BoardModel")
struct BoardModelTests {
    private let nearGrove = StationCatalog.station(.groveStreet).location
    private let near23rd = StationCatalog.station(.twentyThirdStreet).location
    private let nearHoboken = StationCatalog.station(.hoboken).location

    // MARK: Location default

    @Test func deniedThenAuthorizedReResolves() {
        let model = makeModel()
        model.locationDidChange(nil, authorization: .denied)
        #expect(model.trip.sameRoute(as: .groveTo33rd))

        model.locationDidChange(near23rd, authorization: .authorized)
        #expect(model.trip == .goingHome)
    }

    @Test func freshFixReResolves() {
        let model = makeModel()
        model.locationDidChange(nearGrove, authorization: .authorized)
        #expect(model.trip.sameRoute(as: .groveTo33rd))

        model.locationDidChange(near23rd, authorization: .authorized)
        #expect(model.trip == .goingHome)
    }

    @Test func manualStationSelectionSticks() {
        let model = makeModel()
        model.selectStation(.hoboken)
        let chosen = model.trip
        #expect(chosen.origin == .hoboken)

        model.locationDidChange(near23rd, authorization: .authorized)
        model.locationDidChange(nil, authorization: .denied)
        #expect(model.trip == chosen)
    }

    @Test func manualTripSelectionSticks() {
        let model = makeModel()
        model.select(.groveToWTC, manual: true)

        model.locationDidChange(near23rd, authorization: .authorized)
        model.locationDidChange(nearGrove, authorization: .authorized)
        #expect(model.trip == .groveToWTC)
    }

    @Test func locationDefaultDoesNotSaveLastTrip() {
        let store = makeStore()
        let model = BoardModel(store: store, fetch: { throw URLError(.notConnectedToInternet) })
        model.locationDidChange(near23rd, authorization: .authorized)
        #expect(model.trip == .goingHome)
        #expect(store.lastTrip == nil)
    }

    @Test func freshFixWritesLastNearestStation() {
        let store = makeStore()
        let model = BoardModel(store: store, fetch: { throw URLError(.notConnectedToInternet) })
        #expect(store.lastNearestStation == nil)
        model.locationDidChange(near23rd, authorization: .authorized)
        #expect(store.lastNearestStation == .twentyThirdStreet)
        // Even after a manual selection the fix is still remembered.
        model.select(.groveToWTC, manual: true)
        model.locationDidChange(nearHoboken, authorization: .authorized)
        #expect(store.lastNearestStation == .hoboken)
        // No fix / denied never clears it.
        model.locationDidChange(nil, authorization: .denied)
        #expect(store.lastNearestStation == .hoboken)
    }

    @Test func nearHobokenHeadsToGrove() {
        let model = makeModel()
        model.locationDidChange(nearHoboken, authorization: .authorized)
        #expect(model.trip == Trip(origin: .hoboken, destination: .groveStreet))
    }

    @Test func noLocationOrUndeterminedLeavesTrip() {
        let store = makeStore()
        store.lastTrip = Trip(origin: .hoboken, destination: .worldTradeCenter)
        let model = BoardModel(store: store, fetch: { throw URLError(.notConnectedToInternet) })
        let initial = model.trip
        #expect(initial.origin == .hoboken)

        model.locationDidChange(nil, authorization: .authorized)
        #expect(model.trip == initial)
        model.locationDidChange(near23rd, authorization: .notDetermined)
        #expect(model.trip == initial)
        model.locationDidChange(nil, authorization: .notDetermined)
        #expect(model.trip == initial)
    }

    // MARK: Destination

    @Test func unreachableDestinationIsIgnored() {
        let store = makeStore()
        let model = BoardModel(store: store, fetch: { throw URLError(.notConnectedToInternet) })
        let hobokenWTC = Trip(origin: .hoboken, destination: .worldTradeCenter)
        model.select(hobokenWTC, manual: false)

        model.selectDestination(.newark)   // no single line serves Hoboken → Newark
        model.selectDestination(.hoboken)  // the origin itself
        #expect(model.trip == hobokenWTC)
        #expect(store.lastTrip == nil)

        model.selectDestination(.thirtyThirdStreet)
        #expect(model.trip.sameRoute(as: Trip(origin: .hoboken, destination: .thirtyThirdStreet)))
        #expect(store.lastTrip?.sameRoute(as: model.trip) == true)
    }

    // MARK: Refresh

    @Test func concurrentRefreshesShareOneFetch() async {
        let gate = FetchGate()
        let fetchedAt = Date(timeIntervalSince1970: 1_000)
        let model = makeModel {
            await gate.enter()
            return PATHSnapshot(fetchedAt: fetchedAt, boards: [:])
        }

        async let first: Void = model.refresh()
        async let second: Void = model.refresh()

        while await gate.calls == 0 { await Task.yield() }
        // Give the second caller every chance to start its own fetch.
        for _ in 0..<100 { await Task.yield() }
        #expect(await gate.calls == 1)
        #expect(model.isLoading)
        #expect(model.snapshot == nil)

        await gate.release()
        _ = await (first, second)

        #expect(await gate.calls == 1)
        #expect(!model.isLoading)
        #expect(model.snapshot?.fetchedAt == fetchedAt)
        #expect(model.lastFetchAt == fetchedAt)
        #expect(model.errorMessage == nil)
    }

    @Test func failedRefreshKeepsSnapshot() async {
        let initial = PATHSnapshot(fetchedAt: Date(timeIntervalSince1970: 500), boards: [:])
        let fresh = Date(timeIntervalSince1970: 900)
        let script = FetchScript()
        let model = BoardModel(store: makeStore(), initialSnapshot: initial) {
            if await script.next() == 1 { throw URLError(.notConnectedToInternet) }
            return PATHSnapshot(fetchedAt: fresh, boards: [:])
        }
        #expect(model.snapshot?.fetchedAt == initial.fetchedAt)
        #expect(model.lastFetchAt == initial.fetchedAt)

        await model.refresh()
        #expect(model.snapshot?.fetchedAt == initial.fetchedAt)
        #expect(model.lastFetchAt == initial.fetchedAt)
        #expect(model.errorMessage != nil)
        #expect(!model.isLoading)

        await model.refresh()
        #expect(model.snapshot?.fetchedAt == fresh)
        #expect(model.lastFetchAt == fresh)
        #expect(model.errorMessage == nil)
    }

    @Test func refreshAfterCompletionFetchesAgain() async {
        let script = FetchScript()
        let model = makeModel {
            let call = await script.next()
            return PATHSnapshot(fetchedAt: Date(timeIntervalSince1970: TimeInterval(call)), boards: [:])
        }
        await model.refresh()
        await model.refresh()
        #expect(await script.calls == 2)
        #expect(model.lastFetchAt == Date(timeIntervalSince1970: 2))
    }

    // MARK: Helpers

    private func makeStore() -> TripStore {
        let suite = "PATHKitTests.BoardModel.\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        return TripStore(suiteName: suite)
    }

    private func makeModel(
        fetch: @escaping BoardModel.Fetch = { throw URLError(.notConnectedToInternet) }
    ) -> BoardModel {
        BoardModel(store: makeStore(), fetch: fetch)
    }
}

/// Holds every `enter()` caller until `release()`.
private actor FetchGate {
    private(set) var calls = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func enter() async {
        calls += 1
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// Counts fetches; `next()` returns the 1-based call number.
private actor FetchScript {
    private(set) var calls = 0

    func next() -> Int {
        calls += 1
        return calls
    }
}
