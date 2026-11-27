import Foundation

/// A GitHub repository, `owner/name`.
public struct GitHubRepo: Hashable, Sendable {
    public let owner: String
    public let name: String

    public init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    /// Where feedback issues go.
    public static let pathStat = GitHubRepo(owner: "yesh0907", name: "PATH-stat")

    public var fullName: String { "\(owner)/\(name)" }
}

/// An issue GitHub created.
public struct CreatedIssue: Codable, Hashable, Sendable {
    public let number: Int
    public let htmlURL: URL

    public init(number: Int, htmlURL: URL) {
        self.number = number
        self.htmlURL = htmlURL
    }

    enum CodingKeys: String, CodingKey {
        case number
        case htmlURL = "html_url"
    }
}

/// Why a report couldn't be sent (yet).
public enum FeedbackSendError: Error, Equatable, Hashable, Sendable {
    case noToken
    case unauthorized
    case forbidden(String)
    case notFound
    case validation(String)
    case rateLimited
    case network(String)
    case server(Int)

    /// The token is missing, expired, or lacks access: retrying won't help until it changes.
    public var isTokenProblem: Bool {
        switch self {
        case .noToken, .unauthorized, .forbidden, .notFound: true
        case .validation, .rateLimited, .network, .server: false
        }
    }

    public var userMessage: String {
        switch self {
        case .noToken: "No GitHub token set up."
        case .unauthorized: "GitHub rejected the token (expired or revoked)."
        case .forbidden(let message): message.isEmpty ? "The token isn't allowed to do this." : "Not allowed: \(message)"
        case .notFound: "Repository not found. Check the token's repository access."
        case .validation(let message): message.isEmpty ? "GitHub rejected the report." : "GitHub rejected the report: \(message)"
        case .rateLimited: "GitHub rate limit reached."
        case .network: "Can't reach GitHub."
        case .server(let status): "GitHub error \(status)."
        }
    }

    /// Any error from a service call, as a `FeedbackSendError`.
    public static func from(_ error: any Error) -> FeedbackSendError {
        if let error = error as? FeedbackSendError { return error }
        if let error = error as? URLError { return .network(error.localizedDescription) }
        return .network(String(describing: error))
    }
}

/// Where feedback goes. `GitHubClient` in the app; fakes in tests and scenario mode.
public protocol FeedbackIssueService: Sendable {
    /// Creates any of `labels` that don't exist yet.
    func ensureLabels(_ labels: [String]) async throws
    /// Stores a PNG at `path` on the screenshot branch with commit `message`; returns a URL
    /// that renders in issues.
    func uploadScreenshot(_ png: Data, path: String, message: String) async throws -> URL
    func createIssue(_ draft: FeedbackIssueDraft) async throws -> CreatedIssue
    /// Checks the token can see the repository.
    func verifyAccess() async throws
}

/// GitHub REST client for feedback issues. Never logs the token.
public struct GitHubClient: FeedbackIssueService {
    public static let apiBaseURL = URL(string: "https://api.github.com")!
    /// Orphan branch holding screenshots; never merged.
    public static let assetsBranch = "feedback-assets"
    public static let assetsReadme = "Screenshots attached to in-app feedback issues. Written by the PATH Stat app; do not merge.\n"
    public static let labelColors: [String: String] = [
        "feedback": "5319e7",
        "bug": "d73a4a",
        "design-nit": "c5def5",
        "frustration": "fbca04",
        "idea": "a2eeef",
    ]
    public static let labelDescriptions: [String: String] = [
        "feedback": "Sent from the PATH Stat app",
        "bug": "Something isn't working",
        "design-nit": "Small visual or layout issue",
        "frustration": "Works, but annoying to use",
        "idea": "Suggestion or new feature",
    ]
    public static let assetsBranchCommitMessage = "Create feedback-assets branch"
    public static let timeout: TimeInterval = 30

    private let token: String
    public let repo: GitHubRepo
    private let session: URLSession
    private let baseURL: URL

    public init(token: String, repo: GitHubRepo = .pathStat, session: URLSession = .shared, baseURL: URL = apiBaseURL) {
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.repo = repo
        self.session = session
        self.baseURL = baseURL
    }

    // MARK: FeedbackIssueService

    public func ensureLabels(_ labels: [String]) async throws {
        for label in labels {
            let existing = try await send("GET", repoPath("labels", label), accepting: [404])
            guard existing.status == 404 else { continue }
            let body = LabelBody(
                name: label,
                color: Self.labelColors[label] ?? "ededed",
                description: Self.labelDescriptions[label] ?? "PATH Stat feedback"
            )
            let created = try await send("POST", repoPath("labels"), body: body, accepting: [422])
            // Created meanwhile (another device or a concurrent call) counts as success.
            if created.status == 422, !created.text.contains("already_exists") {
                throw Self.error(for: created)
            }
        }
    }

    public func uploadScreenshot(_ png: Data, path: String, message: String) async throws -> URL {
        try await ensureAssetsBranch()
        let body = ContentsBody(
            message: message,
            content: png.base64EncodedString(),
            branch: Self.assetsBranch
        )
        // 422: the file already exists (an earlier attempt uploaded it), which is fine.
        _ = try await send("PUT", repoPath("contents") + "/" + encodePath(path), body: body, accepting: [422])
        return URL(string: "https://github.com/\(repo.owner)/\(repo.name)/blob/\(Self.assetsBranch)/\(encodePath(path))?raw=true")!
    }

    public func createIssue(_ draft: FeedbackIssueDraft) async throws -> CreatedIssue {
        let reply = try await send("POST", repoPath("issues"), body: draft)
        return try decode(CreatedIssue.self, reply)
    }

    public func verifyAccess() async throws {
        _ = try await send("GET", "/repos/\(repo.owner)/\(repo.name)")
    }

    // MARK: Screenshot branch

    /// Creates `feedback-assets` as an orphan branch (just a README) if it doesn't exist, so
    /// screenshots never touch `main`'s history.
    private func ensureAssetsBranch() async throws {
        let ref = try await send("GET", repoPath("git", "ref", "heads", Self.assetsBranch), accepting: [404])
        guard ref.status == 404 else { return }
        let tree = try decode(SHA.self, try await send("POST", repoPath("git", "trees"), body: TreeBody(tree: [
            .init(path: "README.md", mode: "100644", type: "blob", content: Self.assetsReadme),
        ])))
        let commit = try decode(SHA.self, try await send("POST", repoPath("git", "commits"), body: CommitBody(
            message: Self.assetsBranchCommitMessage, tree: tree.sha, parents: []
        )))
        let created = try await send("POST", repoPath("git", "refs"), body: RefBody(
            ref: "refs/heads/\(Self.assetsBranch)", sha: commit.sha
        ), accepting: [422])
        if created.status == 422, !created.text.localizedCaseInsensitiveContains("already exists") {
            throw Self.error(for: created)
        }
    }

    // MARK: HTTP

    struct Reply {
        let status: Int
        let data: Data
        let response: HTTPURLResponse
        var text: String { String(decoding: data, as: UTF8.self) }
    }

    private func repoPath(_ components: String...) -> String {
        "/repos/\(repo.owner)/\(repo.name)/" + components.map(encodePath).joined(separator: "/")
    }

    private func encodePath(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    }

    private func send(_ method: String, _ path: String, accepting extra: Set<Int> = []) async throws -> Reply {
        try await send(method, path, bodyData: nil, accepting: extra)
    }

    private func send(_ method: String, _ path: String, body: some Encodable, accepting extra: Set<Int> = []) async throws -> Reply {
        let data: Data
        do {
            data = try JSONEncoder().encode(body)
        } catch {
            throw FeedbackSendError.validation("Couldn't encode the request.")
        }
        return try await send(method, path, bodyData: data, accepting: extra)
    }

    /// Sends a request; 2xx and `extra` statuses return, anything else throws `FeedbackSendError`.
    private func send(_ method: String, _ path: String, bodyData: Data?, accepting extra: Set<Int>) async throws -> Reply {
        guard !token.isEmpty else { throw FeedbackSendError.noToken }
        guard let url = URL(string: baseURL.absoluteString.trimmingSuffix("/") + path) else {
            throw FeedbackSendError.validation("Bad request path.")
        }
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("PATHStat-feedback", forHTTPHeaderField: "User-Agent")
        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FeedbackSendError.from(error)
        }
        guard let http = response as? HTTPURLResponse else { throw FeedbackSendError.network("Not an HTTP response.") }
        let reply = Reply(status: http.statusCode, data: data, response: http)
        if (200..<300).contains(reply.status) || extra.contains(reply.status) { return reply }
        throw Self.error(for: reply)
    }

    static func error(for reply: Reply) -> FeedbackSendError {
        let message = (try? JSONDecoder().decode(ErrorBody.self, from: reply.data))?.message ?? ""
        switch reply.status {
        case 401: return .unauthorized
        case 403, 429:
            if reply.status == 429 || reply.response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" {
                return .rateLimited
            }
            return .forbidden(message)
        case 404: return .notFound
        case 422: return .validation(message)
        default: return .server(reply.status)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ reply: Reply) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: reply.data)
        } catch {
            throw FeedbackSendError.server(reply.status)
        }
    }

    // MARK: Bodies

    private struct ErrorBody: Decodable { let message: String }
    private struct SHA: Decodable { let sha: String }
    private struct LabelBody: Encodable { let name: String; let color: String; let description: String }
    private struct ContentsBody: Encodable { let message: String; let content: String; let branch: String }
    private struct TreeBody: Encodable {
        struct Entry: Encodable { let path: String; let mode: String; let type: String; let content: String }
        let tree: [Entry]
    }
    private struct CommitBody: Encodable { let message: String; let tree: String; let parents: [String] }
    private struct RefBody: Encodable { let ref: String; let sha: String }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
