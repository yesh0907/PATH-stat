import Foundation
import Testing
@testable import PATHKit

@Suite("PATHClient networking")
struct ClientTests {
    func client(feed: StubURLProtocol.Response, alerts: StubURLProtocol.Response = .http(status: 200, body: Data())) -> PATHClient {
        PATHClient(
            session: StubURLProtocol.session(),
            feedURL: StubURLProtocol.register(feed),
            alertsURL: StubURLProtocol.register(alerts),
            now: { feedBase.addingTimeInterval(10) }
        )
    }

    @Test func successfulFetchUsesInjectedClock() async throws {
        let body = try Fixtures.data("ridepath")
        let snapshot = try await client(feed: .http(status: 200, body: body)).fetchSnapshot()
        #expect(snapshot.fetchedAt == feedBase.addingTimeInterval(10))
        #expect(snapshot.boards.count == 13)
    }

    @Test func departuresConvenience() async throws {
        let body = makeFeed([("GRV", [("ToNY", [
            Msg(target: "33S", seconds: "60", color: "FF9900", headsign: "33rd Street"),
            Msg(target: "WTC", seconds: "90", color: "D93A30", headsign: "World Trade Center"),
        ])])])
        let board = try await client(feed: .http(status: 200, body: body))
            .departures(at: .groveStreet, direction: .toNY, toward: .worldTradeCenter, headsign: nil)
        #expect(board.trains.map(\.target) == [.worldTradeCenter])
    }

    @Test func fetchAlerts() async throws {
        let alerts = try await client(feed: .http(status: 200, body: Data()), alerts: .http(status: 200, body: try Fixtures.data("alerts")))
            .fetchAlerts()
        #expect(alerts.count == 1)
    }

    @Test(arguments: [500, 404, 503])
    func httpErrorStatus(_ status: Int) async {
        await #expect(throws: PATHError.httpStatus(status)) {
            try await client(feed: .http(status: status, body: Data("oops".utf8))).fetchSnapshot()
        }
    }

    @Test(arguments: [
        (URLError.Code.notConnectedToInternet, PATHError.offline),
        (.networkConnectionLost, .offline),
        (.dataNotAllowed, .offline),
        (.cannotFindHost, .offline),
        (.timedOut, .timedOut),
    ])
    func transportErrorMapping(_ code: URLError.Code, _ expected: PATHError) async {
        await #expect(throws: expected) {
            try await client(feed: .failure(code)).fetchSnapshot()
        }
    }

    @Test func malformedBodyIsInvalidResponse() async {
        await #expect {
            try await client(feed: .http(status: 200, body: Data("<html>".utf8))).fetchSnapshot()
        } throws: { error in
            if case PATHError.invalidResponse = error { return true }
            return false
        }
    }

    @Test func errorMappingHelper() {
        #expect(PATHError.from(URLError(.notConnectedToInternet)) == .offline)
        #expect(PATHError.from(URLError(.timedOut)) == .timedOut)
        #expect(PATHError.from(PATHError.httpStatus(502)) == .httpStatus(502))
        if case .invalidResponse = PATHError.from(URLError(.badServerResponse)) {} else {
            Issue.record("expected invalidResponse")
        }
    }
}
