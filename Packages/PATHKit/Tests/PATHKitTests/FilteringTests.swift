import Foundation
import Testing
@testable import PATHKit

@Suite("Toward / headsign filtering")
struct FilteringTests {
    let now = feedBase

    func snapshot(_ station: String, _ label: String, _ messages: [Msg]) throws -> PATHSnapshot {
        try PATHClient.parseSnapshot(makeFeed([(station, [(label, messages)])]), fetchedAt: now)
    }

    @Test func groveTowardThirtyThirdExcludesWTC() throws {
        let fixture = try PATHClient.parseSnapshot(try Fixtures.data("ridepath"), fetchedAt: .now)
        let at = try #require(PATHDateParser.parse("2026-11-26T20:44:02-05:00"))
        let board = fixture.departures(at: .groveStreet, direction: .toNY, toward: .thirtyThirdStreet, now: at)
        #expect(board.trains.map(\.line) == [.journalSquare33rd])
        #expect(board.toward == .thirtyThirdStreet)

        let handcrafted = try snapshot("GRV", "ToNY", [
            Msg(target: "33S", seconds: "60", color: "FF9900", headsign: "33rd Street"),
            Msg(target: "WTC", seconds: "120", color: "D93A30", headsign: "World Trade Center"),
            Msg(target: "33S", seconds: "180", color: "4D92FB,FF9900", headsign: "33rd Street via Hoboken"),
        ])
        let filtered = handcrafted.departures(at: .groveStreet, direction: .toNY, toward: .thirtyThirdStreet, now: now)
        #expect(filtered.trains.map(\.line) == [.journalSquare33rd, .journalSquare33rdViaHoboken])
    }

    @Test func groveTowardWTCIsNewarkWTC() throws {
        let s = try snapshot("GRV", "ToNY", [
            Msg(target: "33S", seconds: "60", color: "FF9900", headsign: "33rd Street"),
            Msg(target: "WTC", seconds: "120", color: "D93A30", headsign: "World Trade Center"),
            Msg(target: "33S", seconds: "180", color: "4D92FB,FF9900", headsign: "33rd Street via Hoboken"),
            Msg(target: "WTC", seconds: "240", color: "D93A30", headsign: "World Trade Center"),
        ])
        let board = s.departures(at: .groveStreet, direction: .toNY, toward: .worldTradeCenter, now: now)
        #expect(board.trains.count == 2)
        #expect(board.trains.allSatisfy { $0.line == .newarkWTC })
    }

    @Test func twentyThirdTowardGroveExcludesHobokenTrains() throws {
        let s = try snapshot("23S", "ToNJ", [
            Msg(target: "HOB", seconds: "60", color: "4D92FB", headsign: "Hoboken"),
            Msg(target: "JSQ", seconds: "120", color: "FF9900", headsign: "Journal Square"),
            Msg(target: "HOB", seconds: "180", color: "4D92FB", headsign: "Hoboken"),
            Msg(target: "JSQ", seconds: "240", color: "4D92FB,FF9900", headsign: "Journal Square via Hoboken"),
        ])
        let board = s.departures(at: .twentyThirdStreet, direction: .toNJ, toward: .groveStreet, now: now)
        #expect(board.trains.map(\.headsign) == ["Journal Square", "Journal Square via Hoboken"])
        #expect(board.trains.map(\.line) == [.journalSquare33rd, .journalSquare33rdViaHoboken])
    }

    @Test(arguments: ["33S", "23S"])
    func uptownTowardHobokenIsHoboken33(_ station: String) throws {
        let s = try snapshot(station, "ToNJ", [
            Msg(target: "JSQ", seconds: "60", color: "FF9900", headsign: "Journal Square"),
            Msg(target: "HOB", seconds: "120", color: "4D92FB", headsign: "Hoboken"),
        ])
        let code = try #require(StationCode(rawValue: station))
        let board = s.departures(at: code, direction: .toNJ, toward: .hoboken, now: now)
        #expect(board.trains.map(\.line) == [.hoboken33rd])
    }

    @Test func fixtureThirtyThirdTowardHoboken() throws {
        let fixture = try PATHClient.parseSnapshot(try Fixtures.data("ridepath"), fetchedAt: .now)
        let at = try #require(PATHDateParser.parse("2026-11-26T20:43:32-05:00"))
        let board = fixture.departures(at: .thirtyThirdStreet, direction: .toNJ, toward: .hoboken, now: at)
        #expect(board.trains.count == 2)
        #expect(board.trains.allSatisfy { $0.line == .hoboken33rd && $0.headsign == "Hoboken" })
    }

    @Test func doesNotMatchStationsBehindTheTrain() throws {
        let s = try snapshot("GRV", "ToNY", [Msg(target: "33S", seconds: "60", color: "FF9900", headsign: "33rd Street")])
        #expect(s.departures(at: .groveStreet, direction: .toNY, toward: .journalSquare, now: now).trains.isEmpty)
        #expect(s.departures(at: .groveStreet, direction: .toNY, toward: .groveStreet, now: now).trains.isEmpty)
        #expect(s.departures(at: .groveStreet, direction: .toNY, toward: .newport, now: now).trains.count == 1)
    }

    @Test func unknownLineFallsBackToTarget() throws {
        let s = try snapshot("GRV", "ToNY", [
            Msg(target: "33S", seconds: "60", color: "123456", headsign: "33rd Street"),
            Msg(target: "WTC", seconds: "120", color: "", headsign: "World Trade Center"),
        ])
        #expect(s.boards[.groveStreet]?[.toNY]?.allSatisfy { $0.line == nil } == true)
        #expect(s.departures(at: .groveStreet, direction: .toNY, toward: .thirtyThirdStreet, now: now).trains.map(\.headsign) == ["33rd Street"])
        // Intermediate stops can't be inferred without a line.
        #expect(s.departures(at: .groveStreet, direction: .toNY, toward: .exchangePlace, now: now).trains.isEmpty)
    }

    @Test func headsignFilterIsCaseInsensitiveSubstring() throws {
        let s = try snapshot("JSQ", "ToNY", [
            Msg(target: "33S", seconds: "60", color: "FF9900", headsign: "33rd Street"),
            Msg(target: "WTC", seconds: "120", color: "D93A30", headsign: "World Trade Center"),
            Msg(target: "33S", seconds: "180", color: "4D92FB,FF9900", headsign: "33rd Street via Hoboken"),
        ])
        #expect(s.departures(at: .journalSquare, direction: .toNY, headsign: "VIA hob", now: now).trains.count == 1)
        #expect(s.departures(at: .journalSquare, direction: .toNY, headsign: "33rd street", now: now).trains.count == 2)
        #expect(s.departures(at: .journalSquare, direction: .toNY, headsign: "world", now: now).trains.count == 1)
        #expect(s.departures(at: .journalSquare, direction: .toNY, headsign: "Newark", now: now).trains.isEmpty)
        #expect(s.departures(at: .journalSquare, direction: .toNY, headsign: "", now: now).trains.count == 3)
        let combined = s.departures(at: .journalSquare, direction: .toNY, toward: .thirtyThirdStreet, headsign: "via", now: now)
        #expect(combined.trains.map(\.line) == [.journalSquare33rdViaHoboken])
    }
}
