import Foundation
import PATHKit

/// Feedback in scenario mode: `-UITestFeedback <sent|offline|noToken>` (default `sent`).
/// In-memory token, throwaway queue directory, stub service; never calls GitHub.
enum FeedbackScenario: String, Sendable {
    /// A token is set and every report becomes issue #42.
    case sent
    /// A token is set but GitHub is unreachable; reports stay queued.
    case offline
    /// No token; reports stay queued until one is added.
    case noToken

    static let argument = "-UITestFeedback"
    static let scenarioToken = "github_pat_SCENARIO0000"

    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> FeedbackScenario {
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else { return .sent }
        return FeedbackScenario(rawValue: arguments[index + 1]) ?? .sent
    }

    @MainActor
    func makeCenter() -> FeedbackCenter {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "PATHStatFeedback-\(UUID().uuidString)", directoryHint: .isDirectory)
        let service = StubFeedbackService(scenario: self)
        return FeedbackCenter(
            queue: FeedbackQueue(directory: directory),
            tokenStore: InMemoryTokenStore(token: self == .noToken ? nil : Self.scenarioToken),
            isLive: false,
            makeService: { token in token == nil ? nil : service }
        )
    }
}

/// Fixed GitHub responses for scenario mode.
struct StubFeedbackService: FeedbackIssueService {
    let scenario: FeedbackScenario

    static let issue = CreatedIssue(number: 42, htmlURL: URL(string: "https://github.com/yesh0907/PATH-stat/issues/42")!)

    private func check() throws {
        if scenario == .offline { throw FeedbackSendError.network("The Internet connection appears to be offline.") }
    }

    func ensureLabels(_ labels: [String]) async throws { try check() }

    func uploadScreenshot(_ png: Data, path: String, message: String) async throws -> URL {
        try check()
        return URL(string: "https://github.com/yesh0907/PATH-stat/blob/\(GitHubClient.assetsBranch)/\(path)?raw=true")!
    }

    func createIssue(_ draft: FeedbackIssueDraft) async throws -> CreatedIssue {
        try check()
        return Self.issue
    }

    func verifyAccess() async throws { try check() }
}
