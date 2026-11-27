import Foundation
import Testing
@testable import PATHKit

/// `GitHubClient` against a routed stub host: exact requests, bodies and status mapping.
/// Never touches the real GitHub API.
@Suite("GitHub feedback client")
struct GitHubClientTests {
    static let repoPath = "/repos/yesh0907/PATH-stat"

    /// A client on a fresh stub host, and that host's base URL for reading recorded requests.
    func client(token: String = "github_pat_TESTTOKEN1234", _ route: @escaping StubURLProtocol.Route) -> (GitHubClient, URL) {
        let base = StubURLProtocol.registerHost(route)
        return (GitHubClient(token: token, session: StubURLProtocol.session(), baseURL: base), base)
    }

    // MARK: Headers

    @Test func headersAndTimeout() async throws {
        let (client, base) = client { _ in .json(200, #"{"full_name":"yesh0907/PATH-stat"}"#) }
        try await client.verifyAccess()
        let requests = StubURLProtocol.requests(to: base)
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.method == "GET")
        #expect(request.path == Self.repoPath)
        #expect(request.header("Authorization") == "Bearer github_pat_TESTTOKEN1234")
        #expect(request.header("Accept") == "application/vnd.github+json")
        #expect(request.header("X-GitHub-Api-Version") == "2022-11-28")
        #expect(request.header("User-Agent") == "PATHStat-feedback")
        #expect(GitHubClient.timeout == 30)
    }

    @Test func tokenIsTrimmed() async throws {
        let (client, base) = client(token: "  tok123 \n") { _ in .json(200) }
        try await client.verifyAccess()
        #expect(StubURLProtocol.requests(to: base).first?.header("Authorization") == "Bearer tok123")
    }

    @Test func emptyTokenNeverSends() async {
        let (client, base) = client(token: "  ") { _ in .json(200) }
        await #expect(throws: FeedbackSendError.noToken) { try await client.verifyAccess() }
        #expect(StubURLProtocol.requests(to: base).isEmpty)
    }

    // MARK: Issues

    @Test func createIssueSendsExactBody() async throws {
        let (client, base) = client { _ in
            .json(201, #"{"number":42,"html_url":"https://github.com/yesh0907/PATH-stat/issues/42","title":"x"}"#)
        }
        let draft = FeedbackIssueDraft(title: "Countdown froze", body: "Body\n<!-- id -->", labels: ["feedback", "bug"])
        let issue = try await client.createIssue(draft)
        #expect(issue == CreatedIssue(number: 42, htmlURL: URL(string: "https://github.com/yesh0907/PATH-stat/issues/42")!))
        let request = try #require(StubURLProtocol.requests(to: base).first)
        #expect(request.method == "POST")
        #expect(request.path == "\(Self.repoPath)/issues")
        #expect(request.header("Content-Type") == "application/json")
        let json = try #require(request.json)
        #expect(Set(json.keys) == ["title", "body", "labels"])
        #expect(json["title"] as? String == "Countdown froze")
        #expect(json["body"] as? String == "Body\n<!-- id -->")
        #expect(json["labels"] as? [String] == ["feedback", "bug"])
    }

    // MARK: Status mapping

    @Test(arguments: [
        (401, [String: String](), #"{"message":"Bad credentials"}"#, FeedbackSendError.unauthorized),
        (403, ["x-ratelimit-remaining": "0"], #"{"message":"API rate limit exceeded"}"#, .rateLimited),
        (403, ["x-ratelimit-remaining": "4999"], #"{"message":"Resource not accessible by personal access token"}"#,
         .forbidden("Resource not accessible by personal access token")),
        (404, [:], #"{"message":"Not Found"}"#, .notFound),
        (422, [:], #"{"message":"Validation Failed"}"#, .validation("Validation Failed")),
        (500, [:], "oops", .server(500)),
        (503, [:], "", .server(503)),
    ])
    func statusMapping(_ status: Int, _ headers: [String: String], _ body: String, _ expected: FeedbackSendError) async {
        let (client, _) = client { _ in .json(status, body, headers: headers) }
        await #expect(throws: expected) {
            try await client.createIssue(FeedbackIssueDraft(title: "t", body: "b", labels: []))
        }
    }

    @Test func networkErrorMapsToNetwork() async {
        let (client, _) = client { _ in .failure(.notConnectedToInternet) }
        do {
            try await client.verifyAccess()
            Issue.record("expected an error")
        } catch let error as FeedbackSendError {
            guard case .network = error else { Issue.record("got \(error)"); return }
            #expect(!error.isTokenProblem)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func tokenProblems() {
        #expect(FeedbackSendError.noToken.isTokenProblem)
        #expect(FeedbackSendError.unauthorized.isTokenProblem)
        #expect(FeedbackSendError.forbidden("x").isTokenProblem)
        #expect(FeedbackSendError.notFound.isTokenProblem)
        #expect(!FeedbackSendError.rateLimited.isTokenProblem)
        #expect(!FeedbackSendError.server(502).isTokenProblem)
        #expect(!FeedbackSendError.validation("x").isTokenProblem)
        #expect(FeedbackSendError.server(502).userMessage == "GitHub error 502.")
    }

    // MARK: Labels

    @Test func ensureLabelsCreatesOnlyMissingWithExactColors() async throws {
        let (client, base) = client { request in
            switch (request.method, request.path) {
            case ("GET", "\(Self.repoPath)/labels/feedback"): .json(200, #"{"name":"feedback"}"#)
            case ("GET", _): .json(404, #"{"message":"Not Found"}"#)
            case ("POST", "\(Self.repoPath)/labels"): .json(201)
            default: .json(500)
            }
        }
        try await client.ensureLabels(FeedbackIssueFormatter.allLabels)
        let requests = StubURLProtocol.requests(to: base)
        #expect(requests.filter { $0.method == "GET" }.map(\.path) == FeedbackIssueFormatter.allLabels.map { "\(Self.repoPath)/labels/\($0)" })
        let posts = requests.filter { $0.method == "POST" }.compactMap(\.json)
        #expect(posts.count == 4)
        #expect(posts.allSatisfy { Set($0.keys) == ["name", "color", "description"] })
        #expect(posts.allSatisfy { !(($0["description"] as? String) ?? "").isEmpty })
        let colors = Dictionary(uniqueKeysWithValues: posts.map { ($0["name"] as! String, $0["color"] as! String) })
        #expect(colors == ["bug": "d73a4a", "design-nit": "c5def5", "frustration": "fbca04", "idea": "a2eeef"])
        #expect(GitHubClient.labelColors["feedback"] == "5319e7")
    }

    @Test func ensureLabelsTreatsAlreadyExistsAsSuccess() async throws {
        let (client, base) = client { request in
            request.method == "GET"
                ? .json(404)
                : .json(422, #"{"message":"Validation Failed","errors":[{"resource":"Label","code":"already_exists","field":"name"}]}"#)
        }
        try await client.ensureLabels(["bug"])
        #expect(StubURLProtocol.requests(to: base).map(\.method) == ["GET", "POST"])
    }

    @Test func ensureLabelsOtherValidationFails() async {
        let (client, _) = client { request in
            request.method == "GET" ? .json(404) : .json(422, #"{"message":"Validation Failed","errors":[{"code":"invalid"}]}"#)
        }
        await #expect(throws: FeedbackSendError.validation("Validation Failed")) { try await client.ensureLabels(["bug"]) }
    }

    // MARK: Screenshots

    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
    static let path = "screenshots/2026-11-27/11111111-2222-3333-4444-555555555555.png"
    static let message = "Add feedback screenshot 11111111-2222-3333-4444-555555555555"
    static let rawURL = "https://github.com/yesh0907/PATH-stat/blob/feedback-assets/\(path)?raw=true"

    @Test func uploadToExistingBranch() async throws {
        let (client, base) = client { request in
            switch (request.method, request.path) {
            case ("GET", "\(Self.repoPath)/git/ref/heads/feedback-assets"): .json(200, #"{"ref":"refs/heads/feedback-assets"}"#)
            case ("PUT", "\(Self.repoPath)/contents/\(Self.path)"): .json(201, #"{"content":{}}"#)
            default: .json(500)
            }
        }
        let url = try await client.uploadScreenshot(Self.png, path: Self.path, message: Self.message)
        #expect(url.absoluteString == Self.rawURL)
        let requests = StubURLProtocol.requests(to: base)
        #expect(requests.map(\.method) == ["GET", "PUT"])
        let put = try #require(requests.last?.json)
        #expect(Set(put.keys) == ["message", "content", "branch"])
        #expect(put["branch"] as? String == "feedback-assets")
        #expect(put["message"] as? String == Self.message)
        #expect(put["content"] as? String == Self.png.base64EncodedString())
    }

    @Test func uploadCreatesOrphanBranchInOrder() async throws {
        let (client, base) = client { request in
            switch (request.method, request.path) {
            case ("GET", _): .json(404, #"{"message":"Not Found"}"#)
            case ("POST", "\(Self.repoPath)/git/trees"): .json(201, #"{"sha":"tree111"}"#)
            case ("POST", "\(Self.repoPath)/git/commits"): .json(201, #"{"sha":"commit222"}"#)
            case ("POST", "\(Self.repoPath)/git/refs"): .json(201, #"{"ref":"refs/heads/feedback-assets"}"#)
            case ("PUT", _): .json(201)
            default: .json(500)
            }
        }
        let url = try await client.uploadScreenshot(Self.png, path: Self.path, message: Self.message)
        #expect(url.absoluteString == Self.rawURL)
        let requests = StubURLProtocol.requests(to: base)
        #expect(requests.map { "\($0.method) \($0.path)" } == [
            "GET \(Self.repoPath)/git/ref/heads/feedback-assets",
            "POST \(Self.repoPath)/git/trees",
            "POST \(Self.repoPath)/git/commits",
            "POST \(Self.repoPath)/git/refs",
            "PUT \(Self.repoPath)/contents/\(Self.path)",
        ])
        let tree = try #require(requests[1].json)
        #expect(Set(tree.keys) == ["tree"])
        let entry = try #require((tree["tree"] as? [[String: Any]])?.first)
        #expect(entry["path"] as? String == "README.md")
        #expect(entry["mode"] as? String == "100644")
        #expect(entry["type"] as? String == "blob")
        #expect(entry["content"] as? String == "Screenshots attached to in-app feedback issues. Written by the PATH Stat app; do not merge.\n")
        let commit = try #require(requests[2].json)
        #expect(Set(commit.keys) == ["message", "tree", "parents"])
        #expect(commit["message"] as? String == "Create feedback-assets branch")
        #expect(commit["tree"] as? String == "tree111")
        #expect((commit["parents"] as? [Any])?.isEmpty == true)
        let ref = try #require(requests[3].json)
        #expect(Set(ref.keys) == ["ref", "sha"])
        #expect(ref["ref"] as? String == "refs/heads/feedback-assets")
        #expect(ref["sha"] as? String == "commit222")
    }

    @Test func refAlreadyExistsAndFileAlreadyExistsAreSuccess() async throws {
        let (client, base) = client { request in
            switch (request.method, request.path) {
            case ("GET", "\(Self.repoPath)/contents/\(Self.path)"): .json(200, #"{"sha":"x"}"#)
            case ("GET", _): .json(404)
            case ("POST", "\(Self.repoPath)/git/refs"): .json(422, #"{"message":"Reference already exists"}"#)
            case ("POST", _): .json(201, #"{"sha":"abc"}"#)
            case ("PUT", _): .json(422, #"{"message":"Invalid request.\n\n\"sha\" wasn't supplied."}"#)
            default: .json(500)
            }
        }
        let url = try await client.uploadScreenshot(Self.png, path: Self.path, message: Self.message)
        #expect(url.absoluteString == Self.rawURL)
        let requests = StubURLProtocol.requests(to: base)
        #expect(requests.count == 6)
        let contentsGet = try #require(requests.last)
        #expect(contentsGet.method == "GET")
        #expect(contentsGet.path == "\(Self.repoPath)/contents/\(Self.path)")
        #expect(contentsGet.url.query() == "ref=feedback-assets")
    }

    @Test func putValidationFailureWithoutFileThrowsValidation() async throws {
        let (client, base) = client { request in
            switch (request.method, request.path) {
            case ("GET", "\(Self.repoPath)/git/ref/heads/feedback-assets"): .json(200, #"{"ref":"refs/heads/feedback-assets"}"#)
            case ("GET", "\(Self.repoPath)/contents/\(Self.path)"): .json(404, #"{"message":"Not Found"}"#)
            case ("PUT", _): .json(422, #"{"message":"Validation Failed","errors":[{"code":"invalid"}]}"#)
            default: .json(500)
            }
        }
        await #expect(throws: FeedbackSendError.validation("Validation Failed")) {
            _ = try await client.uploadScreenshot(Self.png, path: Self.path, message: Self.message)
        }
        #expect(StubURLProtocol.requests(to: base).map(\.method) == ["GET", "PUT", "GET"])
    }

    @Test func uploadFailureMapsStatus() async {
        let (client, _) = client { _ in .json(403, #"{"message":"Resource not accessible by personal access token"}"#) }
        await #expect(throws: FeedbackSendError.forbidden("Resource not accessible by personal access token")) {
            _ = try await client.uploadScreenshot(Self.png, path: Self.path, message: Self.message)
        }
    }
}
