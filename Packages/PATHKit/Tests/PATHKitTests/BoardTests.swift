import Foundation
import Testing
@testable import PATHKit

@Suite("DepartureBoard")
struct BoardTests {
    let snapshot: PATHSnapshot

    init() throws {
        snapshot = try PATHClient.parseSnapshot(makeFeed([
            ("GRV", [("ToNY", [
                Msg(target: "WTC", seconds: "300", color: "D93A30", headsign: "World Trade Center"),
                Msg(target: "33S", seconds: "0", color: "FF9900", headsign: "33rd Street"),
                Msg(target: "33S", seconds: "120", color: "FF9900", headsign: "33rd Street"),
                Msg(target: "WTC", seconds: "30", color: "D93A30", headsign: "World Trade Center",
                    lastUpdated: "2026-11-26T19:59:30.000000-05:00"),
            ])]),
        ]), fetchedAt: feedBase)
    }

    @Test func sortedAndNextFollowing() throws {
        let board = snapshot.departures(at: .groveStreet, direction: .toNY, now: feedBase)
        #expect(board.trains.map { $0.arrival.timeIntervalSince(feedBase) } == [0, 0, 120, 300])
        let next = try #require(board.next)
        let following = try #require(board.following)
        #expect(next.arrival <= following.arrival)
        #expect(board.trains.count == 4)
    }

    @Test func departedTrainsDroppedAfterGrace() {
        // 60 s after base: trains at +0 are exactly 60 s past → still kept.
        let at60 = snapshot.departures(at: .groveStreet, direction: .toNY, now: feedBase.addingTimeInterval(60))
        #expect(at60.trains.count == 4)
        // 61 s: the two +0 trains are gone.
        let at61 = snapshot.departures(at: .groveStreet, direction: .toNY, now: feedBase.addingTimeInterval(61))
        #expect(at61.trains.map { $0.arrival.timeIntervalSince(feedBase) } == [120, 300])
        #expect(at61.next?.target == .thirtyThirdStreet)
        #expect(at61.following?.target == .worldTradeCenter)
        // Far future: board empty, but lastUpdated still known.
        let later = snapshot.departures(at: .groveStreet, direction: .toNY, now: feedBase.addingTimeInterval(3600))
        #expect(later.trains.isEmpty)
        #expect(later.next == nil && later.following == nil)
        #expect(later.lastUpdated == feedBase)
    }

    @Test func singleTrainHasNoFollowing() throws {
        let board = snapshot.departures(at: .groveStreet, direction: .toNY, now: feedBase.addingTimeInterval(200))
        #expect(board.next?.target == .worldTradeCenter)
        #expect(board.following == nil)
    }

    @Test func freshness() {
        let board = snapshot.departures(at: .groveStreet, direction: .toNY, now: feedBase)
        #expect(board.lastUpdated == feedBase) // newest lastUpdated wins
        #expect(board.age(at: feedBase.addingTimeInterval(30)) == 30)
        #expect(board.freshness(at: feedBase.addingTimeInterval(30)) == .fresh(age: 30))
        #expect(board.freshness(at: feedBase.addingTimeInterval(120)) == .fresh(age: 120))
        #expect(board.freshness(at: feedBase.addingTimeInterval(121)) == .stale(age: 121))
        #expect(board.freshness(at: feedBase.addingTimeInterval(45), staleAfter: 30) == .stale(age: 45))
        #expect(board.freshness(at: feedBase.addingTimeInterval(-5)) == .fresh(age: 0))
        let missing = snapshot.departures(at: .newark, direction: .toNY, now: feedBase)
        #expect(missing.age(at: feedBase) == nil)
        #expect(missing.freshness(at: feedBase) == .unknown)
    }

    @Test func remainingTime() throws {
        let train = try #require(snapshot.departures(at: .groveStreet, direction: .toNY, now: feedBase).trains.last)
        #expect(train.secondsRemaining(at: feedBase) == 300)
        #expect(train.minutesRemaining(at: feedBase) == 5)
        #expect(train.secondsRemaining(at: feedBase.addingTimeInterval(400)) == 0)
        #expect(train.minutesRemaining(at: feedBase.addingTimeInterval(400)) == 0)
        #expect(train.minutesRemaining(at: feedBase.addingTimeInterval(275)) == 1)
        #expect(train.minutesRemaining(at: feedBase.addingTimeInterval(150)) == 3) // 150 s → 2.5 → 3
    }
}
