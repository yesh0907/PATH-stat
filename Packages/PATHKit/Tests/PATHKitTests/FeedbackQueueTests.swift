import Foundation
import Testing
@testable import PATHKit

/// A controllable clock for queue tests.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = feedbackBase) { current = start }

    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

/// In-memory `FeedbackIssueService` with scripted failures.
final class FakeIssueService: FeedbackIssueService, @unchecked Sendable {
    private let lock = NSLock()
    private var _uploads: [String] = []
    private var _uploadMessages: [String] = []
    private var _labelCalls: [[String]] = []
    private var _created: [FeedbackIssueDraft] = []
    private var _createAttempts = 0
    /// Called with the 0-based createIssue attempt; a non-nil error fails it.
    var createFailure: @Sendable (Int) -> FeedbackSendError? = { _ in nil }
    var uploadFailure: FeedbackSendError?
    var labelsFailure: FeedbackSendError?
    var delay: Duration?

    var uploads: [String] { lock.withLock { _uploads } }
    var uploadMessages: [String] { lock.withLock { _uploadMessages } }
    var labelCalls: [[String]] { lock.withLock { _labelCalls } }
    var created: [FeedbackIssueDraft] { lock.withLock { _created } }
    var createAttempts: Int { lock.withLock { _createAttempts } }

    func ensureLabels(_ labels: [String]) async throws {
        lock.withLock { _labelCalls.append(labels) }
        if let labelsFailure { throw labelsFailure }
    }

    func uploadScreenshot(_ png: Data, path: String, message: String) async throws -> URL {
        if let uploadFailure { throw uploadFailure }
        lock.withLock {
            _uploads.append(path)
            _uploadMessages.append(message)
        }
        return URL(string: "https://github.com/yesh0907/PATH-stat/blob/feedback-assets/\(path)?raw=true")!
    }

    func createIssue(_ draft: FeedbackIssueDraft) async throws -> CreatedIssue {
        if let delay { try? await Task.sleep(for: delay) }
        let attempt = lock.withLock {
            defer { _createAttempts += 1 }
            return _createAttempts
        }
        if let error = createFailure(attempt) { throw error }
        let number = lock.withLock {
            _created.append(draft)
            return 41 + _created.count
        }
        return CreatedIssue(number: number, htmlURL: URL(string: "https://github.com/yesh0907/PATH-stat/issues/\(number)")!)
    }

    func verifyAccess() async throws {}
}

@Suite("Feedback queue")
struct FeedbackQueueTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "FeedbackQueueTests-\(UUID().uuidString)")
    let clock = TestClock()
    static let png = Data([0x89, 0x50, 0x4E, 0x47, 9, 9, 9])

    func makeQueue() -> FeedbackQueue {
        FeedbackQueue(directory: directory)
    }

    func report(_ note: String, offset: TimeInterval = 0) -> FeedbackReport {
        FeedbackReport(note: note, category: .bug, context: sampleContext(), createdAt: feedbackBase.addingTimeInterval(offset))
    }

    func file(_ name: String) -> URL { directory.appending(path: "pending/\(name)") }

    // MARK: Persistence

    @Test func enqueueWritesScreenshotAndReport() async throws {
        let queue = makeQueue()
        let item = try await queue.enqueue(report("Hello"), screenshot: Self.png)
        #expect(FileManager.default.fileExists(atPath: file("\(item.id.uuidString).png").path))
        #expect(FileManager.default.fileExists(atPath: file("\(item.id.uuidString).json").path))
        #expect(item.hasScreenshot && item.attempts == 0 && item.screenshotURL == nil)

        // A new queue on the same directory sees it (survives relaunch).
        let reopened = makeQueue()
        let pending = await reopened.pending()
        #expect(pending.map(\.id) == [item.id])
        #expect(pending.first?.report.note == "Hello")
        #expect(await reopened.screenshot(for: item.id) == Self.png)
    }

    @Test func enqueueWithoutScreenshot() async throws {
        let queue = makeQueue()
        let item = try await queue.enqueue(report("No pic"), screenshot: nil)
        #expect(!item.hasScreenshot)
        #expect(!FileManager.default.fileExists(atPath: file("\(item.id.uuidString).png").path))
        #expect(await queue.screenshot(for: item.id) == nil)
    }

    @Test func pendingIsOldestFirst() async throws {
        let queue = makeQueue()
        let b = try await queue.enqueue(report("b", offset: 20), screenshot: nil)
        let a = try await queue.enqueue(report("a", offset: 10), screenshot: nil)
        let c = try await queue.enqueue(report("c", offset: 30), screenshot: nil)
        #expect(await queue.pending().map(\.id) == [a.id, b.id, c.id])
    }

    // MARK: No token

    @Test func noServiceLeavesEverythingWaiting() async throws {
        let queue = makeQueue()
        let a = try await queue.enqueue(report("a"), screenshot: Self.png)
        let b = try await queue.enqueue(report("b", offset: 1), screenshot: nil)
        let outcomes = await queue.process(using: nil, now: clock.now, force: true)
        #expect(outcomes == [a.id: .waiting(.noToken), b.id: .waiting(.noToken)])
        let pending = await queue.pending()
        #expect(pending.map(\.attempts) == [0, 0])
        #expect(pending.allSatisfy { $0.nextAttemptAt == nil && $0.lastError == nil })
        #expect(await queue.nextAttemptDate == nil)
    }

    // MARK: Success

    @Test func successUploadsCreatesAndMovesToSent() async throws {
        let queue = makeQueue()
        let service = FakeIssueService()
        let a = try await queue.enqueue(report("First report"), screenshot: Self.png)
        let b = try await queue.enqueue(report("Second report", offset: 1), screenshot: nil)

        let outcomes = await queue.process(using: service, now: clock.now)
        guard case .sent(let issueA)? = outcomes[a.id], case .sent(let issueB)? = outcomes[b.id] else {
            Issue.record("expected both sent: \(outcomes)")
            return
        }
        #expect(issueA.number == 42 && issueB.number == 43)
        #expect(service.uploads == ["screenshots/2026-11-27/\(a.id.uuidString).png"])
        #expect(service.uploadMessages == ["Add feedback screenshot \(a.id.uuidString)"])
        #expect(service.labelCalls == [FeedbackIssueFormatter.allLabels])
        #expect(service.created.map(\.title) == ["First report", "Second report"])
        #expect(service.created[0].labels == ["feedback", "bug"])
        #expect(service.created[0].body.contains("![Screenshot](https://github.com/yesh0907/PATH-stat/blob/feedback-assets/screenshots/2026-11-27/\(a.id.uuidString).png?raw=true)"))
        #expect(service.created[1].body.contains("_No screenshot._"))

        #expect(await queue.pending().isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.appending(path: "pending").path)
        #expect(leftovers.isEmpty)
        let sent = await queue.sent()
        #expect(sent.map(\.id) == [b.id, a.id])
        #expect(sent.map(\.title) == ["Second report", "First report"])
        #expect(sent.map(\.issue.number) == [43, 42])
        #expect(sent.first?.sentAt == feedbackBase)
        // Survives relaunch.
        #expect(await makeQueue().sent() == sent)
    }

    @Test func screenshotPathIsUTCDay() {
        // 2026-11-27T04:59:59Z is still Nov 26 in New York; the path uses UTC.
        let report = FeedbackReport(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            note: "", category: .idea, context: sampleContext(),
            createdAt: Date(timeIntervalSince1970: 1_795_741_200 - 3600 * 2)
        )
        #expect(FeedbackQueue.screenshotPath(for: report) == "screenshots/2026-11-26/11111111-2222-3333-4444-555555555555.png")
    }

    // MARK: Failures

    @Test func backoffSchedule() {
        #expect(FeedbackQueue.backoff(attempts: 1) == 30)
        #expect(FeedbackQueue.backoff(attempts: 2) == 60)
        #expect(FeedbackQueue.backoff(attempts: 3) == 120)
        #expect(FeedbackQueue.backoff(attempts: 7) == 1920)
        #expect(FeedbackQueue.backoff(attempts: 8) == 3600)
        #expect(FeedbackQueue.backoff(attempts: 100) == 3600)
    }

    @Test func networkErrorBacksOffAndStopsTheRest() async throws {
        let queue = makeQueue()
        let service = FakeIssueService()
        service.createFailure = { _ in .network("offline") }
        let a = try await queue.enqueue(report("a"), screenshot: nil)
        let b = try await queue.enqueue(report("b", offset: 1), screenshot: nil)

        let outcomes = await queue.process(using: service, now: clock.now)
        #expect(outcomes == [a.id: .waiting(.network("offline")), b.id: .waiting(.network("offline"))])
        #expect(service.createAttempts == 1)
        var pending = await queue.pending()
        #expect(pending[0].attempts == 1)
        #expect(pending[0].lastError == FeedbackSendError.network("offline").userMessage)
        #expect(pending[0].nextAttemptAt == feedbackBase.addingTimeInterval(30))
        #expect(pending[1].attempts == 0 && pending[1].nextAttemptAt == nil)
        #expect(await queue.nextAttemptDate == feedbackBase.addingTimeInterval(30))

        clock.advance(31)
        await queue.process(using: service, now: clock.now)
        pending = await queue.pending()
        #expect(pending[0].attempts == 2)
        #expect(pending[0].nextAttemptAt == feedbackBase.addingTimeInterval(31 + 60))
    }

    @Test func otherErrorsContinueWithTheRest() async throws {
        let queue = makeQueue()
        let service = FakeIssueService()
        service.createFailure = { $0 == 0 ? .validation("Validation Failed") : nil }
        let a = try await queue.enqueue(report("a"), screenshot: nil)
        let b = try await queue.enqueue(report("b", offset: 1), screenshot: nil)
        let outcomes = await queue.process(using: service, now: clock.now)
        #expect(outcomes[a.id] == .waiting(.validation("Validation Failed")))
        guard case .sent? = outcomes[b.id] else { Issue.record("b should be sent"); return }
        #expect(await queue.pending().map(\.id) == [a.id])
    }

    @Test func labelFailureRetriesOnNextItem() async throws {
        let queue = makeQueue()
        let service = FakeIssueService()
        service.labelsFailure = .forbidden("nope")
        let a = try await queue.enqueue(report("a"), screenshot: nil)
        let b = try await queue.enqueue(report("b", offset: 1), screenshot: nil)
        let outcomes = await queue.process(using: service, now: clock.now)
        #expect(outcomes == [a.id: .waiting(.forbidden("nope")), b.id: .waiting(.forbidden("nope"))])
        #expect(service.labelCalls.count == 2)
        #expect(service.createAttempts == 0)
    }

    @Test func uploadedScreenshotIsNeverUploadedTwice() async throws {
        let queue = makeQueue()
        let service = FakeIssueService()
        service.createFailure = { $0 == 0 ? .server(502) : nil }
        let a = try await queue.enqueue(report("a"), screenshot: Self.png)

        let first = await queue.process(using: service, now: clock.now)
        #expect(first[a.id] == .waiting(.server(502)))
        let afterFailure = try #require(await queue.pending().first)
        #expect(afterFailure.screenshotURL != nil)
        #expect(service.uploads.count == 1)

        let second = await queue.process(using: service, now: clock.now, force: true)
        guard case .sent? = second[a.id] else { Issue.record("expected sent"); return }
        #expect(service.uploads.count == 1)
        #expect(service.created.first?.body.contains(afterFailure.screenshotURL!.absoluteString) == true)
    }

    // MARK: Scheduling

    @Test func notDueIsSkippedUnlessForced() async throws {
        let queue = makeQueue()
        let service = FakeIssueService()
        service.createFailure = { $0 == 0 ? .server(500) : nil }
        let a = try await queue.enqueue(report("a"), screenshot: nil)
        await queue.process(using: service, now: clock.now)
        #expect(service.createAttempts == 1)

        clock.advance(10)   // backoff is 30 s
        let skipped = await queue.process(using: service, now: clock.now)
        #expect(skipped.isEmpty)
        #expect(service.createAttempts == 1)

        let forced = await queue.process(using: service, now: clock.now, force: true)
        guard case .sent? = forced[a.id] else { Issue.record("expected sent"); return }
        #expect(service.createAttempts == 2)
    }

    @Test func dueAfterBackoff() async throws {
        let queue = makeQueue()
        let service = FakeIssueService()
        service.createFailure = { $0 == 0 ? .rateLimited : nil }
        let a = try await queue.enqueue(report("a"), screenshot: nil)
        await queue.process(using: service, now: clock.now)
        clock.advance(30)
        let outcomes = await queue.process(using: service, now: clock.now)
        guard case .sent? = outcomes[a.id] else { Issue.record("expected sent"); return }
    }

    @Test func nextAttemptDateIsEarliest() async throws {
        let queue = makeQueue()
        let service = FakeIssueService()
        service.createFailure = { _ in .server(500) }
        try await queue.enqueue(report("a"), screenshot: nil)
        try await queue.enqueue(report("b", offset: 1), screenshot: nil)
        await queue.process(using: service, now: clock.now)               // both → +30 s
        clock.advance(40)
        await queue.process(using: service, now: clock.now)               // both again → now + 60 s
        try await queue.enqueue(report("c", offset: 2), screenshot: nil)
        #expect(await queue.nextAttemptDate == feedbackBase.addingTimeInterval(100))
        let pending = await queue.pending()
        #expect(pending.map(\.attempts) == [2, 2, 0])
    }

    @Test func sentKeepsNewestTwenty() async throws {
        let queue = makeQueue()
        let service = FakeIssueService()
        var ids: [UUID] = []
        for index in 0..<25 {
            ids.append(try await queue.enqueue(report("r\(index)", offset: TimeInterval(index)), screenshot: nil).id)
        }
        await queue.process(using: service, now: clock.now)
        let sent = await queue.sent()
        #expect(sent.count == 20)
        #expect(sent.map(\.id) == Array(ids.suffix(20).reversed()))
        #expect(await queue.pending().isEmpty)
    }

    // MARK: Concurrency

    @Test func concurrentProcessCreatesEachIssueOnce() async throws {
        let queue = makeQueue()
        let service = FakeIssueService()
        service.delay = .milliseconds(30)
        for index in 0..<3 {
            try await queue.enqueue(report("r\(index)", offset: TimeInterval(index)), screenshot: Self.png)
        }
        async let first = queue.process(using: service, now: clock.now)
        async let second = queue.process(using: service, now: clock.now, force: true)
        async let third = queue.process(using: service, now: clock.now)
        let results = await [first, second, third]
        #expect(service.created.count == 3)
        #expect(service.uploads.count == 3)
        #expect(Set(service.created.map(\.title)) == ["r0", "r1", "r2"])
        for outcomes in results { #expect(outcomes.count == 3) }
        #expect(await queue.sent().count == 3)
    }

    @Test func reportAddedDuringPassIsSentByRerun() async throws {
        let queue = makeQueue()
        let service = FakeIssueService()
        service.delay = .milliseconds(50)
        try await queue.enqueue(report("old"), screenshot: nil)
        async let first = queue.process(using: service, now: clock.now)
        try await Task.sleep(for: .milliseconds(10))
        let late = try await queue.enqueue(report("late", offset: 5), screenshot: nil)
        let joined = await queue.process(using: service, now: clock.now, force: true)
        _ = await first
        guard case .sent? = joined[late.id] else { Issue.record("late report should be sent: \(joined)"); return }
        #expect(service.created.map(\.title) == ["old", "late"])
    }
}
