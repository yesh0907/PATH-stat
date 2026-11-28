import CoreLocation
import Foundation
import Testing
@testable import PATHKit

@Suite("Trip")
struct TripTests {
    @Test func shortNames() {
        let expected: [StationCode: String] = [
            .newark: "Newark", .harrison: "Harrison", .journalSquare: "Journal Sq", .groveStreet: "Grove St",
            .newport: "Newport", .exchangePlace: "Exchange Pl", .hoboken: "Hoboken", .worldTradeCenter: "WTC",
            .christopherStreet: "Christopher St", .ninthStreet: "9th St", .fourteenthStreet: "14th St",
            .twentyThirdStreet: "23rd St", .thirtyThirdStreet: "33rd St",
        ]
        #expect(expected.count == StationCode.allCases.count)
        for (code, short) in expected {
            #expect(StationCatalog.station(code).shortName == short)
        }
    }

    @Test func idTitleAndPresets() {
        #expect(Trip.groveTo33rd.id == "GRV-33S")
        #expect(Trip.groveTo33rd.title == "Grove St → 33rd St")
        #expect(Trip.groveToWTC.title == "Grove St → WTC")
        #expect(Trip.goingHome.title == "Going home")
        #expect(Trip.goingHome.origin == .twentyThirdStreet && Trip.goingHome.destination == .groveStreet)
        #expect(Trip.presets == [.groveTo33rd, .groveToWTC, .goingHome])
        #expect(Trip.route(from: .twentyThirdStreet, to: .groveStreet) == .goingHome)
        #expect(Trip.route(from: .hoboken, to: .worldTradeCenter) == Trip(origin: .hoboken, destination: .worldTradeCenter))
        #expect(Trip(origin: .twentyThirdStreet, destination: .groveStreet).sameRoute(as: .goingHome))
    }

    @Test func codableRoundTrip() throws {
        let trips = [Trip.goingHome, Trip(origin: .hoboken, destination: .ninthStreet)]
        let decoded = try JSONDecoder().decode([Trip].self, from: JSONEncoder().encode(trips))
        #expect(decoded == trips)
    }

    // MARK: Deep links

    @Test func urlRoundTrip() throws {
        #expect(Trip.groveTo33rd.url.absoluteString == "pathstat://trip?from=GRV&to=33S")
        #expect(Trip.goingHome.url.absoluteString == "pathstat://trip?from=23S&to=GRV")
        for trip in Trip.presets {
            #expect(Trip(url: trip.url) == trip)
        }
        let custom = Trip(origin: .hoboken, destination: .worldTradeCenter)
        #expect(Trip(url: custom.url) == custom)
        #expect(Trip(url: try #require(URL(string: "pathstat://trip?to=wtc&from=grv"))) == .groveToWTC)
    }

    @Test(arguments: [
        "pathstat://trip?from=GRV&to=GRV",
        "pathstat://trip?from=NWK&to=HOB",
        "pathstat://trip?from=GRV&to=XYZ",
        "pathstat://trip?from=ABC&to=33S",
        "pathstat://trip?from=GRV",
        "pathstat://trip",
        "pathstat://station?from=GRV&to=33S",
        "https://trip?from=GRV&to=33S",
    ])
    func urlRejects(_ text: String) throws {
        #expect(Trip(url: try #require(URL(string: text))) == nil)
    }
}

@Suite("Destination options")
struct DestinationOptionTests {
    func termini(_ code: StationCode) -> [StationCode] {
        StationCatalog.destinationOptions(from: code).termini.map(\.destination)
    }

    @Test func terminiPerStation() {
        // allCases: newarkWTC, hobokenWTC, journalSquare33rd, hoboken33rd, viaHoboken.
        #expect(termini(.groveStreet) == [.worldTradeCenter, .thirtyThirdStreet, .newark, .journalSquare])
        #expect(termini(.hoboken) == [.worldTradeCenter, .thirtyThirdStreet, .journalSquare])
        #expect(termini(.thirtyThirdStreet) == [.journalSquare, .hoboken])
        #expect(termini(.worldTradeCenter) == [.newark, .hoboken])
        #expect(termini(.newark) == [.worldTradeCenter])
        #expect(termini(.newport) == [.worldTradeCenter, .thirtyThirdStreet, .hoboken, .journalSquare])
    }

    @Test func terminiDirectionsAndLabels() {
        let grove = StationCatalog.destinationOptions(from: .groveStreet).termini
        #expect(grove.map(\.direction) == [.toNY, .toNY, .toNJ, .toNJ])
        #expect(grove.map(\.label) == ["to WTC", "to 33rd St", "to Newark", "to Journal Sq"])
        let hoboken = StationCatalog.destinationOptions(from: .hoboken).termini
        #expect(hoboken.map(\.direction) == [.toNY, .toNY, .toNJ])
    }

    @Test func otherStops() throws {
        let fromTwentyThird = StationCatalog.destinationOptions(from: .twentyThirdStreet)
        #expect(fromTwentyThird.termini.map(\.destination) == [.thirtyThirdStreet, .journalSquare, .hoboken])
        #expect(fromTwentyThird.otherStops.map(\.destination) == [
            .groveStreet, .newport, .christopherStreet, .ninthStreet, .fourteenthStreet,
        ])
        let grove = try #require(fromTwentyThird.otherStops.first)
        #expect(grove.label == "to Grove St")
        #expect(grove.direction == .toNJ)
        #expect(fromTwentyThird.otherStops.allSatisfy { $0.direction == .toNJ })
        let fromHoboken = StationCatalog.destinationOptions(from: .hoboken).otherStops
        #expect(fromHoboken.first { $0.destination == .ninthStreet }?.direction == .toNY)
        #expect(fromHoboken.first { $0.destination == .newport }?.direction == .toNY)

        let fromNewark = StationCatalog.destinationOptions(from: .newark)
        #expect(fromNewark.otherStops.map(\.destination) == [.harrison, .journalSquare, .groveStreet, .exchangePlace])
        #expect(fromNewark.otherStops.allSatisfy { $0.direction == .toNY })
    }

    @Test func optionsCoverExactlyTheReachableStations() {
        for station in StationCode.allCases {
            let options = StationCatalog.destinationOptions(from: station)
            let all = options.termini + options.otherStops
            #expect(!options.termini.isEmpty)
            #expect(Set(all.map(\.destination)).count == all.count)
            let reachable = StationCode.allCases.filter { !StationCatalog.lines(serving: station, to: $0).isEmpty }
            #expect(Set(all.map(\.destination)) == Set(reachable))
            #expect(!all.contains { $0.destination == station })
        }
    }
}

@Suite("Trip board")
struct TripBoardTests {
    let now = feedBase

    @Test func groveToThirtyThirdMergesLinesAndExcludesWTC() throws {
        let s = try PATHClient.parseSnapshot(makeFeed([
            ("GRV", [
                ("ToNY", [
                    Msg(target: "33S", seconds: "180", color: "4D92FB,FF9900", headsign: "33rd Street via Hoboken"),
                    Msg(target: "WTC", seconds: "60", color: "D93A30", headsign: "World Trade Center"),
                    Msg(target: "33S", seconds: "120", color: "FF9900", headsign: "33rd Street"),
                ]),
                ("ToNJ", [
                    Msg(target: "JSQ", seconds: "30", color: "FF9900", headsign: "Journal Square"),
                    Msg(target: "NWK", seconds: "90", color: "D93A30", headsign: "Newark"),
                ]),
            ]),
        ]), fetchedAt: now)
        let board = s.departures(at: .groveStreet, toward: .thirtyThirdStreet, now: now)
        #expect(board.trains.map(\.line) == [.journalSquare33rd, .journalSquare33rdViaHoboken])
        #expect(board.direction == .toNY)
        #expect(board.toward == .thirtyThirdStreet)
        #expect(board.station == .groveStreet)

        let toWTC = s.departures(at: .groveStreet, toward: .worldTradeCenter, now: now)
        #expect(toWTC.trains.map(\.line) == [.newarkWTC])
        let toJSQ = s.departures(at: .groveStreet, toward: .journalSquare, now: now)
        #expect(toJSQ.trains.map(\.target) == [.journalSquare, .newark])
        #expect(toJSQ.direction == .toNJ)
    }

    @Test func twentyThirdToGroveTakesJournalSquareTrainsOnly() throws {
        let s = try PATHClient.parseSnapshot(makeFeed([
            ("23S", [
                ("ToNJ", [
                    Msg(target: "HOB", seconds: "60", color: "4D92FB", headsign: "Hoboken"),
                    Msg(target: "JSQ", seconds: "120", color: "FF9900", headsign: "Journal Square"),
                    Msg(target: "JSQ", seconds: "240", color: "4D92FB,FF9900", headsign: "Journal Square via Hoboken"),
                ]),
                ("ToNY", [
                    Msg(target: "33S", seconds: "30", color: "FF9900", headsign: "33rd Street"),
                ]),
            ]),
        ]), fetchedAt: now)
        let board = s.departures(at: .twentyThirdStreet, toward: .groveStreet, now: now)
        #expect(board.trains.map(\.headsign) == ["Journal Square", "Journal Square via Hoboken"])
        #expect(board.trains.allSatisfy { $0.direction == .toNJ })
        #expect(board.direction == .toNJ)
    }

    @Test func newportToHobokenUsesBothDirections() throws {
        let s = try PATHClient.parseSnapshot(makeFeed([
            ("NEW", [
                ("ToNJ", [
                    Msg(target: "HOB", seconds: "200", color: "65C100", headsign: "Hoboken"),
                    Msg(target: "JSQ", seconds: "50", color: "4D92FB,FF9900", headsign: "Journal Square via Hoboken"),
                    Msg(target: "JSQ", seconds: "70", color: "FF9900", headsign: "Journal Square"),
                ]),
                ("ToNY", [
                    Msg(target: "33S", seconds: "100", color: "4D92FB,FF9900", headsign: "33rd Street via Hoboken"),
                    Msg(target: "33S", seconds: "150", color: "FF9900", headsign: "33rd Street"),
                    Msg(target: "WTC", seconds: "80", color: "65C100", headsign: "World Trade Center"),
                ]),
            ]),
        ]), fetchedAt: now)
        let board = s.departures(at: .newport, toward: .hoboken, now: now)
        #expect(board.trains.map(\.line) == [.journalSquare33rdViaHoboken, .hobokenWTC])
        #expect(board.trains.map(\.direction) == [.toNY, .toNJ])
        // First line in allCases order (Hoboken–WTC) decides the nominal direction.
        #expect(board.direction == .toNJ)
    }

    @Test func departedDroppedAndEmptyBoardKeepsLastUpdated() throws {
        let s = try PATHClient.parseSnapshot(makeFeed([
            ("GRV", [
                ("ToNY", [
                    Msg(target: "33S", seconds: "0", color: "FF9900", headsign: "33rd Street",
                        lastUpdated: "2026-11-26T19:59:00.000000-05:00"),
                    Msg(target: "WTC", seconds: "30", color: "D93A30", headsign: "World Trade Center"),
                ]),
                ("ToNJ", [
                    Msg(target: "JSQ", seconds: "10", color: "FF9900", headsign: "Journal Square",
                        lastUpdated: "2026-11-26T20:00:10.000000-05:00"),
                ]),
            ]),
        ]), fetchedAt: now)
        // 33S train arrived at 19:59:00; at 20:00:00 it is exactly 60 s past → kept.
        #expect(s.departures(at: .groveStreet, toward: .thirtyThirdStreet, now: now).trains.count == 1)
        let later = now.addingTimeInterval(61)
        let board = s.departures(at: .groveStreet, toward: .thirtyThirdStreet, now: later)
        #expect(board.trains.isEmpty)
        // Newest across both directions' unfiltered messages (the ToNJ one).
        #expect(board.lastUpdated == now.addingTimeInterval(10))
        #expect(board.freshness(at: later) == .fresh(age: 51))

        let missing = s.departures(at: .hoboken, toward: .worldTradeCenter, now: now)
        #expect(missing.trains.isEmpty && missing.lastUpdated == nil)
        #expect(missing.direction == .toNY)
    }

    @Test func unreachableDestinationFallsBackToTargetMatch() throws {
        // Newark → Hoboken has no single line; direction defaults to toNY and only an
        // unidentified-line train whose target is HOB could match.
        let s = try PATHClient.parseSnapshot(makeFeed([
            ("NWK", [("ToNY", [
                Msg(target: "WTC", seconds: "60", color: "D93A30", headsign: "World Trade Center"),
                Msg(target: "HOB", seconds: "90", color: "123456", headsign: "Hoboken"),
            ])]),
        ]), fetchedAt: now)
        let board = s.departures(at: .newark, toward: .hoboken, now: now)
        #expect(board.direction == .toNY)
        #expect(board.trains.map(\.headsign) == ["Hoboken"])
    }
}

@Suite("TripPlanner")
struct TripPlannerTests {
    /// ~320 m south-west of Grove St.
    let nearGrove = CLLocation(latitude: 40.7175, longitude: -74.0450)
    /// ~200 m north of 23rd St.
    let nearTwentyThird = CLLocation(latitude: 40.7447, longitude: -73.9920)
    let nearHoboken = CLLocation(latitude: 40.7370, longitude: -74.0300)
    let nearFourteenth = CLLocation(latitude: 40.7380, longitude: -73.9965)
    /// ~2 km south-west of Grove St, still nearest to it.
    let farFromGrove = CLLocation(latitude: 40.7050, longitude: -74.0600)

    func nearest(_ location: CLLocation) -> StationCode? {
        StationCatalog.stations(nearest: location).first?.station.code
    }

    @Test func fixtureLocationsAreWhereTheTestsAssume() {
        #expect(nearest(nearGrove) == .groveStreet)
        #expect(nearest(nearTwentyThird) == .twentyThirdStreet)
        #expect(nearest(nearHoboken) == .hoboken)
        #expect(nearest(nearFourteenth) == .fourteenthStreet)
        #expect(nearest(farFromGrove) == .groveStreet)
    }

    @Test func everyStationReachesGroveStreetOnOneLine() {
        for station in StationCode.allCases where station != .groveStreet {
            #expect(!StationCatalog.lines(serving: station, to: .groveStreet).isEmpty, "\(station) reaches Grove St")
        }
    }

    @Test func smartTrip() {
        #expect(TripPlanner.smartTrip(nearest: nil) == .groveTo33rd)
        #expect(TripPlanner.smartTrip(nearest: .groveStreet) == .groveTo33rd)
        #expect(TripPlanner.smartTrip(nearest: .twentyThirdStreet) == .goingHome)
        #expect(TripPlanner.smartTrip(nearest: .twentyThirdStreet).name == "Going home")
        #expect(TripPlanner.smartTrip(nearest: .hoboken) == Trip(origin: .hoboken, destination: .groveStreet))
        #expect(TripPlanner.smartTrip(nearest: .newark) == Trip(origin: .newark, destination: .groveStreet))
    }

    @Test func nearestStation() {
        #expect(TripPlanner.nearestStation(to: nearGrove) == .groveStreet)
        #expect(TripPlanner.nearestStation(to: nearHoboken) == .hoboken)
    }

    @Test func nearGroveGoesToThirtyThird() {
        #expect(TripPlanner.defaultTrip(location: nearGrove, lastTrip: nil) == .groveTo33rd)
        #expect(TripPlanner.defaultTrip(location: nearGrove, lastTrip: .groveToWTC) == .groveTo33rd)
        // Far from Grove but still nearest to it: same commute preset.
        #expect(TripPlanner.defaultTrip(location: farFromGrove, lastTrip: nil) == .groveTo33rd)
        #expect(TripPlanner.defaultTrip(location: farFromGrove, lastTrip: .goingHome) == .groveTo33rd)
    }

    @Test func nearTwentyThirdGoesHome() {
        #expect(TripPlanner.defaultTrip(location: nearTwentyThird, lastTrip: nil) == .goingHome)
        #expect(TripPlanner.defaultTrip(location: nearTwentyThird, lastTrip: .groveTo33rd).name == "Going home")
    }

    @Test func elsewhereHeadsTowardGrove() {
        #expect(TripPlanner.defaultTrip(location: nearHoboken, lastTrip: nil)
            == Trip(origin: .hoboken, destination: .groveStreet))
        #expect(TripPlanner.defaultTrip(location: nearHoboken, lastTrip: .groveTo33rd)
            == Trip(origin: .hoboken, destination: .groveStreet))
        #expect(TripPlanner.defaultTrip(location: nearFourteenth, lastTrip: nil)
            == Trip(origin: .fourteenthStreet, destination: .groveStreet))
    }

    @Test func noLocation() {
        #expect(TripPlanner.defaultTrip(location: nil, lastTrip: nil) == .groveTo33rd)
        #expect(TripPlanner.defaultTrip(location: nil, lastTrip: .goingHome) == .goingHome)
        let custom = Trip(origin: .hoboken, destination: .ninthStreet)
        #expect(TripPlanner.defaultTrip(location: nil, lastTrip: custom) == custom)
    }

    @Test func quickDestinations() {
        #expect(TripPlanner.quickDestinations(from: .groveStreet) == [.thirtyThirdStreet, .worldTradeCenter])
        #expect(TripPlanner.quickDestinations(from: .twentyThirdStreet) == [.groveStreet, .thirtyThirdStreet])
        #expect(TripPlanner.quickDestinations(from: .hoboken) == [.groveStreet, .thirtyThirdStreet])
        #expect(TripPlanner.quickDestinations(from: .worldTradeCenter) == [.groveStreet, .newark])
        #expect(TripPlanner.quickDestinations(from: .thirtyThirdStreet) == [.groveStreet, .journalSquare])
        for station in StationCode.allCases {
            let quick = TripPlanner.quickDestinations(from: station)
            #expect(quick.count == 2, "\(station)")
            #expect(Set(quick).count == 2, "\(station)")
            #expect(!quick.contains(station), "\(station)")
            for destination in quick {
                #expect(!StationCatalog.lines(serving: station, to: destination).isEmpty, "\(station) → \(destination)")
            }
        }
    }

    @Test func defaultDestination() {
        #expect(TripPlanner.defaultDestination(from: .groveStreet) == .worldTradeCenter)
        #expect(TripPlanner.defaultDestination(from: .twentyThirdStreet) == .thirtyThirdStreet)
        #expect(TripPlanner.defaultDestination(from: .thirtyThirdStreet) == .journalSquare)
        #expect(TripPlanner.defaultDestination(from: .worldTradeCenter) == .newark)
        #expect(TripPlanner.defaultDestination(from: .newark) == .worldTradeCenter)
        // Keep the current destination when it is still reachable.
        #expect(TripPlanner.defaultDestination(from: .newport, preferring: .thirtyThirdStreet) == .thirtyThirdStreet)
        #expect(TripPlanner.defaultDestination(from: .journalSquare, preferring: .groveStreet) == .groveStreet)
        // Unreachable (no single line) or same station → first terminus.
        #expect(TripPlanner.defaultDestination(from: .newark, preferring: .thirtyThirdStreet) == .worldTradeCenter)
        #expect(TripPlanner.defaultDestination(from: .groveStreet, preferring: .groveStreet) == .worldTradeCenter)
        for station in StationCode.allCases {
            let destination = TripPlanner.defaultDestination(from: station)
            #expect(!StationCatalog.lines(serving: station, to: destination).isEmpty)
        }
    }
}

@Suite("TripStore")
struct TripStoreTests {
    /// Runs `body` against a throwaway defaults suite, removed afterwards.
    func withStore(_ body: (TripStore) throws -> Void) rethrows {
        let suite = "PATHKitTests.TripStore.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        try body(TripStore(suiteName: suite))
    }

    @Test func favoritesDefaultToPresets() {
        withStore { store in
            #expect(store.favorites == Trip.presets)
            #expect(store.lastTrip == nil)
        }
    }

    @Test func favoritesPersist() {
        withStore { store in
            let custom = Trip(origin: .hoboken, destination: .worldTradeCenter, name: "Hoboken run")
            store.favorites = [.goingHome, custom]
            #expect(store.favorites == [.goingHome, custom])
            // A second store on the same suite sees the same data.
            #expect(TripStore(suiteName: store.suiteName).favorites == [.goingHome, custom])
            store.favorites = []
            #expect(store.favorites.isEmpty)
        }
    }

    @Test func lastNearestStationPersistsAndClears() {
        withStore { store in
            #expect(store.lastNearestStation == nil)
            store.lastNearestStation = .hoboken
            #expect(store.lastNearestStation == .hoboken)
            #expect(TripStore(suiteName: store.suiteName).lastNearestStation == .hoboken)
            store.lastNearestStation = nil
            #expect(store.lastNearestStation == nil)
        }
    }

    @Test func lastTripPersistsAndClears() {
        withStore { store in
            store.lastTrip = .goingHome
            #expect(TripStore(suiteName: store.suiteName).lastTrip == .goingHome)
            store.lastTrip = nil
            #expect(store.lastTrip == nil)
        }
    }

    @Test func suitesAreIsolated() {
        withStore { a in
            withStore { b in
                a.lastTrip = .groveToWTC
                #expect(b.lastTrip == nil)
            }
        }
    }
}
