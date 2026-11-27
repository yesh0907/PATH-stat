import Foundation
import Testing
@testable import PATHKit

/// 2026-11-27T01:00:00Z (Thanksgiving evening, 20:00 in New York).
let feedbackBase = Date(timeIntervalSince1970: 1_795_741_200)

func sampleContext(
    screen: String = "main",
    notices: [String] = [],
    lastFeedError: String? = nil
) -> FeedbackContext {
    FeedbackContext(
        appVersion: "0.1 (1)",
        gitCommit: "abc123def456",
        osVersion: "27.0",
        deviceModel: "iPhone18,1",
        screen: screen,
        trip: FeedbackContext.tripDescription(.groveTo33rd),
        stationContext: "nearest",
        locationPermission: "authorized",
        feedFetchedAt: feedbackBase.addingTimeInterval(-12),
        feedAgeSeconds: 12,
        feedFreshness: "fresh",
        lastFeedError: lastFeedError,
        recentNotices: notices,
        liveActivity: "Off",
        appearance: "dark",
        dynamicTypeSize: "large",
        timestamp: feedbackBase
    )
}

func sampleReport(
    id: UUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
    note: String = "Countdown froze\nIt stuck at 2:13 for a minute.",
    category: FeedbackCategory = .bug,
    context: FeedbackContext = sampleContext(),
    createdAt: Date = feedbackBase.addingTimeInterval(5)
) -> FeedbackReport {
    FeedbackReport(id: id, note: note, category: category, context: context, createdAt: createdAt)
}

@Suite("Feedback issue formatting")
struct FeedbackFormatterTests {
    @Test func categories() {
        #expect(FeedbackCategory.allCases.map(\.label) == ["bug", "design-nit", "frustration", "idea"])
        #expect(FeedbackCategory.allCases.map(\.title) == ["Bug", "Design nit", "Frustration", "Idea"])
        #expect(FeedbackCategory(rawValue: "design-nit") == .designNit)
    }

    @Test func tripDescription() {
        #expect(FeedbackContext.tripDescription(.groveTo33rd) == "Grove St → 33rd St (GRV → 33S)")
        #expect(FeedbackContext.tripDescription(.goingHome) == "Going home (23S → GRV)")
    }

    @Test func labels() {
        let draft = FeedbackIssueFormatter.draft(for: sampleReport(category: .designNit), screenshotURL: nil)
        #expect(draft.labels == ["feedback", "design-nit"])
        #expect(FeedbackIssueFormatter.allLabels == ["feedback", "bug", "design-nit", "frustration", "idea"])
    }

    // MARK: Title

    @Test func titleIsFirstNonEmptyLineCollapsed() {
        let report = sampleReport(note: "\n   \n  Countdown   froze\tat  Grove  \nsecond line")
        #expect(FeedbackIssueFormatter.title(for: report) == "Countdown froze at Grove")
    }

    @Test func titleOfExactlyEightyIsKept() {
        let line = String(repeating: "a", count: 80)
        #expect(FeedbackIssueFormatter.title(for: sampleReport(note: line)) == line)
    }

    @Test func longTitleCutsAtWordBoundary() {
        let note = String(repeating: "word ", count: 30)
        let title = FeedbackIssueFormatter.title(for: sampleReport(note: note))
        #expect(title.count <= 80)
        #expect(title.hasSuffix("word…"))
        #expect(title == Array(repeating: "word", count: 15).joined(separator: " ") + "…")
    }

    @Test func longTitleWithoutSpacesIsHardCut() {
        let title = FeedbackIssueFormatter.title(for: sampleReport(note: String(repeating: "x", count: 120)))
        #expect(title == String(repeating: "x", count: 79) + "…")
    }

    @Test func emptyNoteFallsBackToCategoryAndScreen() {
        let report = sampleReport(note: "  \n\t ", category: .frustration, context: sampleContext(screen: "station picker"))
        #expect(FeedbackIssueFormatter.title(for: report) == "Frustration on station picker")
    }

    // MARK: Body

    @Test func exactBody() throws {
        let report = sampleReport(context: sampleContext(notices: ["20:00:01 Can't reach PATH", "20:00:30 A | B"], lastFeedError: "Line one\nline two"))
        let url = URL(string: "https://github.com/yesh0907/PATH-stat/blob/feedback-assets/screenshots/2026-11-27/x.png?raw=true")!
        let body = FeedbackIssueFormatter.body(for: report, screenshotURL: url)
        let expected = """
        Countdown froze
        It stuck at 2:13 for a minute.

        ![Screenshot](https://github.com/yesh0907/PATH-stat/blob/feedback-assets/screenshots/2026-11-27/x.png?raw=true)

        <details>
        <summary>Context</summary>

        | Field | Value |
        |---|---|
        | Category | Bug |
        | App version | 0.1 (1) |
        | Git commit | abc123def456 |
        | iOS | 27.0 |
        | Device | iPhone18,1 |
        | Screen | main |
        | Trip | Grove St → 33rd St (GRV → 33S) |
        | Station | nearest |
        | Location permission | authorized |
        | Feed updated | 2026-11-27T00:59:48Z |
        | Feed age | 12 s |
        | Feed freshness | fresh |
        | Last feed error | Line one line two |
        | Recent notices | 20:00:01 Can't reach PATH<br>20:00:30 A \\| B |
        | Live Activity | Off |
        | Appearance | dark |
        | Dynamic Type | large |
        | Reported at | 2026-11-27T01:00:05Z |
        | Report ID | 11111111-2222-3333-4444-555555555555 |

        ```json
        \(FeedbackIssueFormatter.contextJSON(report.context))
        ```
        </details>
        <!-- pathstat-feedback-id: 11111111-2222-3333-4444-555555555555 -->
        """
        #expect(body == expected)
    }

    @Test func emptyNoteAndNoScreenshot() {
        let body = FeedbackIssueFormatter.body(for: sampleReport(note: " \n "), screenshotURL: nil)
        #expect(body.hasPrefix("_No note._\n\n_No screenshot._\n\n<details>\n<summary>Context</summary>\n\n| Field | Value |\n|---|---|\n| Category | Bug |"))
        #expect(body.hasSuffix("```\n</details>\n<!-- pathstat-feedback-id: 11111111-2222-3333-4444-555555555555 -->"))
    }

    @Test func missingValuesShowDash() {
        var context = sampleContext()
        context.gitCommit = nil
        context.trip = nil
        context.feedFetchedAt = nil
        context.feedAgeSeconds = nil
        let body = FeedbackIssueFormatter.body(for: sampleReport(context: context), screenshotURL: nil)
        #expect(body.contains("| Git commit | — |"))
        #expect(body.contains("| Trip | — |"))
        #expect(body.contains("| Feed updated | — |"))
        #expect(body.contains("| Recent notices | — |"))
    }

    @Test func contextJSONIsSortedWithISODates() throws {
        let json = FeedbackIssueFormatter.contextJSON(sampleContext(notices: ["20:00:01 Offline"]))
        #expect(json.contains("\"timestamp\" : \"2026-11-27T01:00:00Z\""))
        #expect(json.contains("\"feedFetchedAt\" : \"2026-11-27T00:59:48Z\""))
        let keys = json.split(separator: "\n")
            .filter { $0.hasPrefix("  \"") }
            .map { $0.dropFirst(3).prefix { $0 != "\"" } }
            .map(String.init)
        #expect(keys == keys.sorted())
        #expect(Set(keys) == [
            "appVersion", "gitCommit", "osVersion", "deviceModel", "screen", "trip", "stationContext",
            "locationPermission", "feedFetchedAt", "feedAgeSeconds", "feedFreshness", "recentNotices",
            "liveActivity", "appearance", "dynamicTypeSize", "timestamp",
        ])
        // Round-trips.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FeedbackContext.self, from: Data(json.utf8))
        #expect(decoded == sampleContext(notices: ["20:00:01 Offline"]))
    }

    @Test func noLocationDataAnywhere() throws {
        let report = sampleReport()
        let body = FeedbackIssueFormatter.body(for: report, screenshotURL: nil).lowercased()
        for forbidden in ["latitude", "longitude", "coordinate", "\"lat\"", "\"lon\"", "40.7", "-74.0", "distance"] {
            #expect(!body.contains(forbidden), "body mentions \(forbidden)")
        }
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report.context)) as! [String: Any]
        #expect(object.keys.filter { $0.lowercased().contains("location") } == ["locationPermission"])
    }

    // MARK: Recent notices

    @Test func recentNoticesRingAndDedup() {
        var notices = RecentNotices(timeZone: TimeZone(identifier: "America/New_York")!)
        notices.record("Can't reach PATH", at: feedbackBase)
        notices.record("Can't reach PATH", at: feedbackBase.addingTimeInterval(30))   // same, within 60 s
        #expect(notices.descriptions == ["20:00:00 Can't reach PATH"])
        notices.record("Can't reach PATH", at: feedbackBase.addingTimeInterval(61))   // same, later
        notices.record("Stale", at: feedbackBase.addingTimeInterval(62))
        notices.record("Can't reach PATH", at: feedbackBase.addingTimeInterval(63))   // not the newest
        #expect(notices.notices.count == 4)
        for second in 70..<75 { notices.record("N\(second)", at: feedbackBase.addingTimeInterval(TimeInterval(second))) }
        #expect(notices.descriptions == [
            "20:01:10 N70", "20:01:11 N71", "20:01:12 N72", "20:01:13 N73", "20:01:14 N74",
        ])
    }
}
