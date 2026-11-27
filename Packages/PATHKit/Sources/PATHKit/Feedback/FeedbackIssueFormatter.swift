import Foundation

/// A GitHub issue ready to create.
public struct FeedbackIssueDraft: Codable, Hashable, Sendable {
    public var title: String
    public var body: String
    public var labels: [String]

    public init(title: String, body: String, labels: [String]) {
        self.title = title
        self.body = body
        self.labels = labels
    }
}

/// Turns a `FeedbackReport` into a GitHub issue. The body format is a contract with the
/// triage automation (see AGENTS.md "Feedback pipeline"): note, screenshot, a collapsed
/// context table plus the context as JSON, and a hidden report-ID comment.
public enum FeedbackIssueFormatter {
    /// Every feedback issue carries this label plus its category's.
    public static let feedbackLabel = "feedback"
    /// `feedback` and every category label.
    public static let allLabels = [feedbackLabel] + FeedbackCategory.allCases.map(\.label)
    public static let maxTitleLength = 80

    public static func draft(for report: FeedbackReport, screenshotURL: URL?) -> FeedbackIssueDraft {
        FeedbackIssueDraft(
            title: title(for: report),
            body: body(for: report, screenshotURL: screenshotURL),
            labels: [feedbackLabel, report.category.label]
        )
    }

    /// The note's first non-empty line (whitespace collapsed, at most 80 characters, cut at a
    /// word boundary with "…"), else "Bug on main".
    public static func title(for report: FeedbackReport) -> String {
        let firstLine = report.note
            .components(separatedBy: .newlines)
            .lazy
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .first { !$0.isEmpty }
        guard let line = firstLine else {
            return "\(report.category.title) on \(report.context.screen)"
        }
        guard line.count > maxTitleLength else { return line }
        let room = String(line.prefix(maxTitleLength - 1))
        if let space = room.lastIndex(of: " "), space > room.startIndex {
            return room[..<space].trimmingCharacters(in: .whitespaces) + "…"
        }
        return room + "…"
    }

    public static func body(for report: FeedbackReport, screenshotURL: URL?) -> String {
        let note = report.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let screenshot = screenshotURL.map { "![Screenshot](\($0.absoluteString))" } ?? "_No screenshot._"
        var lines = [
            note.isEmpty ? "_No note._" : note,
            "",
            screenshot,
            "",
            "<details>",
            "<summary>Context</summary>",
            "",
            "| Field | Value |",
            "|---|---|",
        ]
        lines += rows(for: report).map { "| \($0.0) | \(escape($0.1)) |" }
        lines += [
            "",
            "```json",
            contextJSON(report.context),
            "```",
            "</details>",
            "<!-- pathstat-feedback-id: \(report.id.uuidString) -->",
        ]
        return lines.joined(separator: "\n")
    }

    /// The context as pretty-printed JSON with sorted keys and ISO 8601 dates.
    public static func contextJSON(_ context: FeedbackContext) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(context) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func rows(for report: FeedbackReport) -> [(String, String)] {
        let c = report.context
        let none = "—"
        return [
            ("Category", report.category.title),
            ("App version", c.appVersion),
            ("Git commit", c.gitCommit ?? none),
            ("iOS", c.osVersion),
            ("Device", c.deviceModel),
            ("Screen", c.screen),
            ("Trip", c.trip ?? none),
            ("Station", c.stationContext ?? none),
            ("Location permission", c.locationPermission ?? none),
            ("Feed updated", c.feedFetchedAt.map(iso8601) ?? none),
            ("Feed age", c.feedAgeSeconds.map { "\($0) s" } ?? none),
            ("Feed freshness", c.feedFreshness ?? none),
            ("Last feed error", c.lastFeedError ?? none),
            ("Recent notices", c.recentNotices.isEmpty ? none : c.recentNotices.joined(separator: "<br>")),
            ("Live Activity", c.liveActivity ?? none),
            ("Appearance", c.appearance),
            ("Dynamic Type", c.dynamicTypeSize),
            ("Reported at", iso8601(report.createdAt)),
            ("Report ID", report.id.uuidString),
        ]
    }

    /// UTC, e.g. "2026-11-27T01:41:07Z".
    static func iso8601(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle())
    }

    /// Table-cell safe: pipes escaped, line breaks turned into spaces.
    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}
