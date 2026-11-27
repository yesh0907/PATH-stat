import Foundation
import Testing
@testable import PATHKit

@Suite("PATHDateParser")
struct DateParserTests {
    // 2026-11-27T01:44:07Z
    let reference = Date(timeIntervalSince1970: 1_795_743_847)

    @Test func sixDigitFractionWithOffset() throws {
        let date = try #require(PATHDateParser.parse("2026-11-26T20:44:07.263779-05:00"))
        #expect(abs(date.timeIntervalSince(reference) - 0.263779) < 1e-5)
    }

    @Test(arguments: [
        "2026-11-26T20:44:07-05:00",
        "2026-11-27T01:44:07Z",
        "2026-11-27T01:44:07.000Z",
        "2026-11-27T01:44:07+00:00",
        "2026-11-27T03:44:07+0200",
        "2026-11-26T20:44:07-05",
        "2026-11-26 20:44:07-05:00",
        "2026-11-26T20:44:07", // no offset → America/New_York (EST in November)
    ])
    func equivalentForms(_ text: String) throws {
        let date = try #require(PATHDateParser.parse(text))
        #expect(date == reference)
    }

    @Test func millisecondAndNanosecondFractions() throws {
        let ms = try #require(PATHDateParser.parse("2026-11-27T01:44:07.5Z"))
        #expect(ms.timeIntervalSince(reference) == 0.5)
        let ns = try #require(PATHDateParser.parse("2026-11-27T01:44:07.123456789Z"))
        #expect(abs(ns.timeIntervalSince(reference) - 0.123456789) < 1e-5)
    }

    @Test(arguments: [
        "", "garbage", "2026-11-26", "2026-11-26T20:44", "2026-11-26T20:44:07.-05:00",
        "2026-13-26T20:44:07Z", "2026-02-30T20:44:07Z", "2026-11-26T25:44:07Z", "2026-11-26T20:44:07Q",
        "2026-11-26T20:44:07Zjunk", "2026-11-26T12:00:60Z", "2026-11-26T23:59:60Z",
    ])
    func rejectsInvalid(_ text: String) {
        #expect(PATHDateParser.parse(text) == nil)
    }
}
