import Foundation
import Testing
@testable import PATHKit

@Suite("Snapshot Codable")
struct SnapshotCodableTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000.25)

    @Test func lineRoundTrips() throws {
        let data = try JSONEncoder().encode(PATHLine.allCases)
        #expect(try JSONDecoder().decode([PATHLine].self, from: data) == PATHLine.allCases)
    }

    @Test func trainArrivalRoundTripsKeepingID() throws {
        let train = TrainArrival(
            id: "custom-id", station: .groveStreet, direction: .toNY, target: nil, headsign: "33rd Street",
            line: nil, lineColors: [], arrival: now, arrivalTimeMessage: "1 min", lastUpdated: now
        )
        let decoded = try JSONDecoder().decode(TrainArrival.self, from: JSONEncoder().encode(train))
        #expect(decoded == train)
        #expect(decoded.id == "custom-id")
    }

    @Test func boardsDictionaryRoundTrips() throws {
        let snapshot = PATHSnapshot.sampleTrains(now: now)
        let decoded = try JSONDecoder().decode(PATHSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded.fetchedAt == snapshot.fetchedAt)
        #expect(decoded.boards == snapshot.boards)
        #expect(decoded.boards.count == StationCode.allCases.count)
    }

    @Test func boardsEncodeAsKeyedObjects() throws {
        let snapshot = PATHSnapshot.sampleTrains(now: now)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        let boards = try #require(json["boards"] as? [String: [String: Any]])
        #expect(boards["GRV"]?["ToNY"] != nil)
    }

    @Test func parsedFeedRoundTrips() throws {
        let snapshot = try PATHClient.parseSnapshot(Fixtures.data("ridepath"), fetchedAt: now)
        let decoded = try JSONDecoder().decode(PATHSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded.boards == snapshot.boards)
    }
}

@Suite("SampleSnapshots")
struct SampleSnapshotTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func trainsAtEveryStation() {
        let snapshot = PATHSnapshot.sampleTrains(now: now)
        #expect(snapshot.fetchedAt == now)
        // Journal Square–33rd St at Grove St (index 1): 252 + 47 − 4 s old feed.
        let board = snapshot.departures(at: .groveStreet, toward: .thirtyThirdStreet, now: now)
        #expect(board.next?.arrival == now.addingTimeInterval(295))
        #expect(board.next?.line == .journalSquare33rd)
        #expect(board.next?.headsign == "33rd Street")
        #expect(board.lastUpdated == now.addingTimeInterval(-4))
        let via = board.trains.first { $0.line == .journalSquare33rdViaHoboken }
        #expect(via?.headsign == "33rd Street via Hoboken")
        #expect(via?.lineColors == ["4D92FB", "FF9900"])
        for station in StationCode.allCases {
            for option in StationCatalog.destinationOptions(from: station).termini {
                #expect(snapshot.departures(at: station, toward: option.destination, now: now).trains.count >= 3)
            }
        }
        // Termini have no trains toward their own end.
        #expect(snapshot.boards[.thirtyThirdStreet]?[.toNY] == nil)
    }

    @Test func noTrainsHasOnlyDepartedTrains() {
        let snapshot = PATHSnapshot.sampleNoTrains(now: now)
        for station in StationCode.allCases {
            for direction in Direction.allCases {
                let board = snapshot.departures(at: station, direction: direction, now: now)
                #expect(board.trains.isEmpty)
            }
            #expect(snapshot.boards[station]?.values.flatMap { $0 }.allSatisfy { $0.lastUpdated == now.addingTimeInterval(-3) } == true)
        }
    }
}

@Suite("SnapshotCache")
struct SnapshotCacheTests {
    func withCache(_ body: (SnapshotCache) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "PATHKitTests.SnapshotCache.\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(SnapshotCache(directory: directory))
    }

    @Test func missingFileLoadsNil() throws {
        try withCache { cache in #expect(cache.load() == nil) }
    }

    @Test func saveThenLoad() throws {
        try withCache { cache in
            let first = PATHSnapshot.sampleTrains(now: Date(timeIntervalSince1970: 1_000))
            cache.save(first)
            #expect(cache.fileURL.lastPathComponent == "latest-snapshot.json")
            #expect(cache.load()?.boards == first.boards)

            let second = PATHSnapshot.sampleNoTrains(now: Date(timeIntervalSince1970: 2_000))
            cache.save(second)
            #expect(cache.load()?.fetchedAt == second.fetchedAt)
            #expect(SnapshotCache(directory: cache.directory).load()?.boards == second.boards)
        }
    }

    @Test func corruptFileLoadsNil() throws {
        try withCache { cache in
            try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
            try Data("{not json".utf8).write(to: cache.fileURL)
            #expect(cache.load() == nil)
            // A later save replaces the corrupt file.
            cache.save(PATHSnapshot(fetchedAt: Date(timeIntervalSince1970: 5), boards: [:]))
            #expect(cache.load()?.fetchedAt == Date(timeIntervalSince1970: 5))
        }
    }
}

@Suite("TripStore migration")
struct TripStoreMigrationTests {
    func withStores(_ body: (_ legacy: TripStore, _ shared: TripStore) throws -> Void) rethrows {
        let a = "PATHKitTests.Legacy.\(UUID().uuidString)"
        let b = "PATHKitTests.Shared.\(UUID().uuidString)"
        defer {
            UserDefaults(suiteName: a)?.removePersistentDomain(forName: a)
            UserDefaults(suiteName: b)?.removePersistentDomain(forName: b)
        }
        try body(TripStore(suiteName: a), TripStore(suiteName: b))
    }

    @Test func appGroupSuiteName() {
        #expect(TripStore.appGroupSuite == "group.com.yesh0907.PATHStat")
    }

    @Test func copiesOnce() {
        withStores { legacy, shared in
            let custom = Trip(origin: .hoboken, destination: .worldTradeCenter, name: "Hoboken run")
            legacy.favorites = [custom]
            legacy.lastTrip = .groveToWTC

            shared.migrateIfNeeded(from: legacy)
            #expect(shared.favorites == [custom])
            #expect(shared.lastTrip == .groveToWTC)

            // Later changes on either side aren't clobbered by another migration.
            shared.favorites = [.goingHome]
            shared.lastTrip = .goingHome
            legacy.favorites = [.groveTo33rd]
            legacy.lastTrip = .groveTo33rd
            shared.migrateIfNeeded(from: legacy)
            #expect(shared.favorites == [.goingHome])
            #expect(shared.lastTrip == .goingHome)
        }
    }

    @Test func doesNotOverwriteExistingData() {
        withStores { legacy, shared in
            legacy.favorites = [.groveToWTC]
            legacy.lastTrip = .groveToWTC
            shared.favorites = []
            shared.migrateIfNeeded(from: legacy)
            #expect(shared.favorites.isEmpty)
            #expect(shared.lastTrip == nil)
        }
    }

    @Test func emptyLegacyMarksMigrated() {
        withStores { legacy, shared in
            shared.migrateIfNeeded(from: legacy)
            #expect(shared.favorites == Trip.presets)
            #expect(shared.lastTrip == nil)
            #expect(shared.hasSavedFavorites)

            // Data the legacy store gains afterwards is not copied.
            legacy.lastTrip = .groveToWTC
            shared.migrateIfNeeded(from: legacy)
            #expect(shared.lastTrip == nil)
        }
    }

    @Test func sameSuiteIsNoOp() {
        withStores { legacy, _ in
            legacy.migrateIfNeeded(from: TripStore(suiteName: legacy.suiteName))
            #expect(!legacy.hasSavedFavorites)
        }
    }
}
