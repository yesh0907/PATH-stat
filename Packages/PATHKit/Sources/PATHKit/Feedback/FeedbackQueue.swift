import Foundation

/// A report waiting to become a GitHub issue.
public struct QueuedFeedback: Codable, Identifiable, Hashable, Sendable {
    public var report: FeedbackReport
    /// A PNG is stored next to the report (`pending/<id>.png`).
    public var hasScreenshot: Bool
    /// Set once the screenshot is uploaded, so a retry never uploads it twice.
    public var screenshotURL: URL?
    public var attempts: Int
    /// `FeedbackSendError.userMessage` of the last failure.
    public var lastError: String?
    /// Not retried before this (unless forced). Nil: due now.
    public var nextAttemptAt: Date?

    public var id: UUID { report.id }

    public init(report: FeedbackReport, hasScreenshot: Bool, screenshotURL: URL? = nil, attempts: Int = 0, lastError: String? = nil, nextAttemptAt: Date? = nil) {
        self.report = report
        self.hasScreenshot = hasScreenshot
        self.screenshotURL = screenshotURL
        self.attempts = attempts
        self.lastError = lastError
        self.nextAttemptAt = nextAttemptAt
    }
}

/// A report that became an issue.
public struct SentFeedback: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let issue: CreatedIssue
    public let sentAt: Date

    public init(id: UUID, title: String, issue: CreatedIssue, sentAt: Date) {
        self.id = id
        self.title = title
        self.issue = issue
        self.sentAt = sentAt
    }
}

/// What happened to one report during `FeedbackQueue.process`.
public enum FeedbackDeliveryOutcome: Hashable, Sendable {
    case sent(CreatedIssue)
    /// Still queued; it will be retried.
    case waiting(FeedbackSendError)
}

/// Durable outbox for feedback. Every report is written to disk before any network call and
/// stays until GitHub has created its issue, so nothing is lost offline or without a token.
///
/// Layout: `pending/<id>.png` (optional) and `pending/<id>.json`, plus `sent.json` (the last
/// 20 sent, newest first).
public actor FeedbackQueue {
    public static let sentLimit = 20
    public static let maxBackoff: TimeInterval = 3600
    public static let baseBackoff: TimeInterval = 30

    public let directory: URL
    private let fileManager = FileManager.default

    private var inFlight: Task<[UUID: FeedbackDeliveryOutcome], Never>?
    private var rerun: (service: (any FeedbackIssueService)?, now: Date, force: Bool)?

    public init(directory: URL) {
        self.directory = directory
    }

    private var pendingDirectory: URL { directory.appending(path: "pending", directoryHint: .isDirectory) }
    private var sentFile: URL { directory.appending(path: "sent.json") }
    private func jsonFile(_ id: UUID) -> URL { pendingDirectory.appending(path: "\(id.uuidString).json") }
    private func pngFile(_ id: UUID) -> URL { pendingDirectory.appending(path: "\(id.uuidString).png") }

    // MARK: Reading

    /// Waiting reports, oldest first.
    public func pending() -> [QueuedFeedback] {
        let files = (try? fileManager.contentsOfDirectory(at: pendingDirectory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Self.decoder.decode(QueuedFeedback.self, from: Data(contentsOf: $0)) }
            .sorted { ($0.report.createdAt, $0.id.uuidString) < ($1.report.createdAt, $1.id.uuidString) }
    }

    /// The last 20 sent reports, newest first.
    public func sent() -> [SentFeedback] {
        guard let data = try? Data(contentsOf: sentFile) else { return [] }
        return (try? Self.decoder.decode([SentFeedback].self, from: data)) ?? []
    }

    public func screenshot(for id: UUID) -> Data? {
        try? Data(contentsOf: pngFile(id))
    }

    /// The earliest scheduled retry among waiting reports.
    public var nextAttemptDate: Date? {
        pending().compactMap(\.nextAttemptAt).min()
    }

    // MARK: Writing

    /// Saves a report (screenshot first, then the report, both atomically), so a report on disk
    /// always has its screenshot.
    @discardableResult
    public func enqueue(_ report: FeedbackReport, screenshot: Data?) throws -> QueuedFeedback {
        try fileManager.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
        if let screenshot {
            try screenshot.write(to: pngFile(report.id), options: .atomic)
        }
        let item = QueuedFeedback(report: report, hasScreenshot: screenshot != nil)
        try save(item)
        return item
    }

    private func save(_ item: QueuedFeedback) throws {
        try Self.encoder.encode(item).write(to: jsonFile(item.id), options: .atomic)
    }

    private func markSent(_ item: QueuedFeedback, issue: CreatedIssue, at now: Date) throws {
        let record = SentFeedback(id: item.id, title: FeedbackIssueFormatter.title(for: item.report), issue: issue, sentAt: now)
        let sent = Array(([record] + sent().filter { $0.id != item.id }).prefix(Self.sentLimit))
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(sent).write(to: sentFile, options: .atomic)
        try? fileManager.removeItem(at: jsonFile(item.id))
        try? fileManager.removeItem(at: pngFile(item.id))
    }

    // MARK: Delivery

    /// Tries to send waiting reports, oldest first, as of `now`. Single-flight: a call made while a pass is
    /// running joins it, and one more pass runs afterwards for anything that call adds.
    ///
    /// - `service == nil` (no token): every report is `waiting(.noToken)`; nothing changes on disk.
    /// - Reports whose `nextAttemptAt` is in the future are skipped unless `force`.
    /// - A network error stops the pass (the rest are reported waiting with it, unchanged).
    @discardableResult
    public func process(using service: (any FeedbackIssueService)?, now: Date = .now, force: Bool = false) async -> [UUID: FeedbackDeliveryOutcome] {
        if let inFlight {
            rerun = (service ?? rerun?.service, max(now, rerun?.now ?? now), force || (rerun?.force ?? false))
            return await inFlight.value
        }
        let task = Task { await self.runPasses(service: service, now: now, force: force) }
        inFlight = task
        return await task.value
    }

    private func runPasses(service: (any FeedbackIssueService)?, now: Date, force: Bool) async -> [UUID: FeedbackDeliveryOutcome] {
        var outcomes = await pass(service: service, now: now, force: force)
        while let next = rerun {
            rerun = nil
            outcomes.merge(await pass(service: next.service ?? service, now: next.now, force: next.force)) { _, new in new }
        }
        // Cleared synchronously after the last rerun check, so no caller can be left behind.
        inFlight = nil
        return outcomes
    }

    private func pass(service: (any FeedbackIssueService)?, now: Date, force: Bool) async -> [UUID: FeedbackDeliveryOutcome] {
        let items = pending()
        guard let service else {
            return Dictionary(uniqueKeysWithValues: items.map { ($0.id, .waiting(.noToken)) })
        }
        var outcomes: [UUID: FeedbackDeliveryOutcome] = [:]
        var labelsReady = false
        for (index, original) in items.enumerated() {
            if !force, let next = original.nextAttemptAt, next > now { continue }
            var item = original
            do {
                if item.hasScreenshot, item.screenshotURL == nil {
                    guard let png = screenshot(for: item.id) else { throw FeedbackSendError.validation("Screenshot file missing.") }
                    item.screenshotURL = try await service.uploadScreenshot(
                        png,
                        path: Self.screenshotPath(for: item.report),
                        message: Self.screenshotCommitMessage(for: item.report)
                    )
                    // Persist at once, so a later failure never uploads it again.
                    try? save(item)
                }
                if !labelsReady {
                    try await service.ensureLabels(FeedbackIssueFormatter.allLabels)
                    labelsReady = true
                }
                let issue = try await service.createIssue(FeedbackIssueFormatter.draft(for: item.report, screenshotURL: item.screenshotURL))
                try? markSent(item, issue: issue, at: now)
                outcomes[item.id] = .sent(issue)
            } catch {
                let failure = FeedbackSendError.from(error)
                item.attempts += 1
                item.lastError = failure.userMessage
                item.nextAttemptAt = now.addingTimeInterval(Self.backoff(attempts: item.attempts))
                try? save(item)
                outcomes[item.id] = .waiting(failure)
                if case .network = failure {
                    for rest in items[(index + 1)...] where outcomes[rest.id] == nil {
                        outcomes[rest.id] = .waiting(failure)
                    }
                    break
                }
            }
        }
        return outcomes
    }

    /// 30 s, 60 s, 120 s, … capped at 1 h.
    public static func backoff(attempts: Int) -> TimeInterval {
        let exponent = max(0, min(attempts - 1, 20))
        return min(baseBackoff * pow(2, Double(exponent)), maxBackoff)
    }

    /// "Add feedback screenshot <id>": the commit message for a report's screenshot.
    public static func screenshotCommitMessage(for report: FeedbackReport) -> String {
        "Add feedback screenshot \(report.id.uuidString)"
    }

    /// `screenshots/2026-11-27/<id>.png`, dated in UTC.
    public static func screenshotPath(for report: FeedbackReport) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day], from: report.createdAt)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "screenshots/\(day)/\(report.id.uuidString).png"
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
