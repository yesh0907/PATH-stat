import Foundation
import Testing
@testable import PATHKit

/// Hits the real PANYNJ endpoints. Run with `PATH_LIVE=1 swift test --package-path Packages/PATHKit`.
@Suite("Live feed", .enabled(if: ProcessInfo.processInfo.environment["PATH_LIVE"] == "1"))
struct LiveFeedTests {
    @Test(.timeLimit(.minutes(1)))
    func groveStreetHasBoards() async throws {
        let snapshot = try await PATHClient().fetchSnapshot()
        let grove = try #require(snapshot.boards[.groveStreet])
        #expect(!grove.isEmpty)
        let board = snapshot.departures(at: .groveStreet, direction: .toNY)
        #expect(board.lastUpdated != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func alertsParse() async throws {
        _ = try await PATHClient().fetchAlerts()
    }
}
