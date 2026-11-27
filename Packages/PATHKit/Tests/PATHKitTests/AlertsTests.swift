import Foundation
import Testing
@testable import PATHKit

@Suite("Service alerts")
struct AlertsTests {
    @Test func parsesFixture() throws {
        let alerts = try PATHClient.parseAlerts(try Fixtures.data("alerts"))
        let alert = try #require(alerts.first)
        #expect(alerts.count == 1)
        #expect(alert.subject == "PATHAlert Update: Track Condition")
        #expect(alert.lines == ["HOB-WTC", "HOB-33"])
        #expect(alert.stations == [.hoboken])
        #expect(alert.createdAt == Date(timeIntervalSince1970: 1_795_743_259.198))
        #expect(alert.modifiedAt == alert.createdAt)
        #expect(alert.message.hasPrefix("08:34 PM: HOB-WTC, HOB-33 suspended."))
        #expect(alert.message.hasSuffix("HBLR: HOB, NWPT, EXPL"))
        #expect(alert.message == alert.message.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(!alert.id.isEmpty)
    }

    @Test func emptyAndMalformed() throws {
        #expect(try PATHClient.parseAlerts(Data(#"{"status":"Success","data":[]}"#.utf8)).isEmpty)
        #expect(throws: PATHError.self) { try PATHClient.parseAlerts(Data("nope".utf8)) }
        #expect(throws: PATHError.self) { try PATHClient.parseAlerts(Data(#"{"status":"Success"}"#.utf8)) }
    }

    @Test func sortedNewestFirstAndToleratesMissingFields() throws {
        let json = """
        {"status":"Success","data":[
          {"incidentMessage":{"subject":"Old","preMessage":"  a  "},"CreatedDate":"1000","ModifiedDate":"2000"},
          {"incidentMessage":{"subject":"New","formVariableItems":[{"variableName":"Station","val":["NWPT","XYZ","33S"]}]},"CreatedDate":"5000"},
          {"incidentMessage":{"subject":"No date"}}
        ]}
        """
        let alerts = try PATHClient.parseAlerts(Data(json.utf8))
        #expect(alerts.map(\.subject) == ["New", "Old"])
        #expect(alerts[0].stations == [.newport, .thirtyThirdStreet])
        #expect(alerts[0].message == "")
        #expect(alerts[1].message == "a")
        #expect(alerts[1].modifiedAt == Date(timeIntervalSince1970: 2))
    }
}
