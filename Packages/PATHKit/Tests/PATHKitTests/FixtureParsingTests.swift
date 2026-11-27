import Foundation
import Testing
@testable import PATHKit

@Suite("Realtime fixture parsing")
struct FixtureParsingTests {
    let snapshot: PATHSnapshot

    init() throws {
        snapshot = try PATHClient.parseSnapshot(try Fixtures.data("ridepath"), fetchedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func allThirteenStationsPresent() {
        #expect(snapshot.boards.count == 13)
        #expect(Set(snapshot.boards.keys) == Set(StationCode.allCases))
    }

    @Test func groveStreetToNYFirstTrain() throws {
        let trains = try #require(snapshot.boards[.groveStreet]?[.toNY])
        let first = try #require(trains.first)
        #expect(first.target == .thirtyThirdStreet)
        #expect(first.headsign == "33rd Street")
        #expect(first.line == .journalSquare33rd)
        #expect(first.lineColors == ["FF9900"])
        #expect(first.arrivalTimeMessage == "1 min")
        let expectedUpdated = try #require(PATHDateParser.parse("2026-11-26T20:44:02.212216-05:00"))
        #expect(first.lastUpdated == expectedUpdated)
        #expect(first.arrival == first.lastUpdated.addingTimeInterval(25))
        #expect(first.arrival.timeIntervalSince(first.lastUpdated) == 25)
    }

    @Test func multiColorLineIsViaHoboken() throws {
        let trains = try #require(snapshot.boards[.journalSquare]?[.toNY])
        let via = try #require(trains.first { $0.lineColors.count == 2 })
        #expect(via.lineColors == ["4D92FB", "FF9900"])
        #expect(via.line == .journalSquare33rdViaHoboken)
        #expect(via.headsign == "33rd Street via Hoboken")
    }

    @Test func everyFixtureTrainHasIdentifiedLineAndTarget() {
        let all = snapshot.boards.values.flatMap(\.values).flatMap { $0 }
        #expect(all.count == 51)
        #expect(all.allSatisfy { $0.line != nil && $0.target != nil })
        #expect(Set(all.map(\.id)).count == all.count)
    }

    @Test func boardsAreSortedByArrival() {
        for directions in snapshot.boards.values {
            for trains in directions.values {
                #expect(trains.map(\.arrival) == trains.map(\.arrival).sorted())
            }
        }
    }

    @Test func terminalsOnlyHaveOneDirection() {
        #expect(snapshot.boards[.newark]?.keys.sorted { $0.rawValue < $1.rawValue } == [.toNY])
        #expect(snapshot.boards[.worldTradeCenter]?.keys.sorted { $0.rawValue < $1.rawValue } == [.toNJ])
    }
}

@Suite("Snapshot parsing edge cases")
struct SnapshotEdgeCaseTests {
    @Test func emptyResultsGiveEmptyBoards() throws {
        let snapshot = try PATHClient.parseSnapshot(Data(#"{"results":[]}"#.utf8), fetchedAt: .now)
        #expect(snapshot.boards.isEmpty)
        let board = snapshot.departures(at: .groveStreet, direction: .toNY)
        #expect(board.trains.isEmpty)
        #expect(board.lastUpdated == nil)
        #expect(board.freshness(at: .now) == .unknown)
    }

    @Test(arguments: ["not json", "", "[]", #"{"foo":1}"#, #"{"results":"nope"}"#])
    func malformedThrowsInvalidResponse(_ body: String) {
        #expect {
            try PATHClient.parseSnapshot(Data(body.utf8), fetchedAt: .now)
        } throws: { error in
            if case PATHError.invalidResponse = error { return true }
            return false
        }
    }

    @Test func unknownStationsLabelsAndBadSecondsAreSkipped() throws {
        let data = makeFeed([
            ("XYZ", [("ToNY", [Msg(target: "33S", seconds: "10", color: "FF9900", headsign: "33rd Street")])]),
            ("GRV", [
                ("Sideways", [Msg(target: "33S", seconds: "10", color: "FF9900", headsign: "33rd Street")]),
                ("ToNY", [
                    Msg(target: "33S", seconds: "soon", color: "FF9900", headsign: "33rd Street"),
                    Msg(target: "33S", seconds: "60", color: "FF9900", headsign: "33rd Street", lastUpdated: "garbage"),
                    Msg(target: "ZZZ", seconds: "120", color: "ABCDEF", headsign: "Mystery"),
                    Msg(target: "WTC", seconds: "30", color: "D93A30", headsign: "World Trade Center"),
                ]),
            ]),
        ])
        let snapshot = try PATHClient.parseSnapshot(data, fetchedAt: .now)
        #expect(Array(snapshot.boards.keys) == [.groveStreet])
        #expect(Array(snapshot.boards[.groveStreet]!.keys) == [.toNY])
        let trains = snapshot.boards[.groveStreet]![.toNY]!
        #expect(trains.map(\.headsign) == ["World Trade Center", "Mystery"])
        #expect(trains[1].target == nil)
        #expect(trains[1].line == nil)
    }
}
