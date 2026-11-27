import Foundation
@testable import PATHKit

enum Fixtures {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}

/// One message in a handcrafted feed.
struct Msg {
    var target: String
    var seconds: String
    var color: String
    var headsign: String
    var lastUpdated = "2026-11-26T20:00:00.000000-05:00"
}

/// Builds a realtime-feed JSON payload: station → label → messages.
func makeFeed(_ stations: [(String, [(String, [Msg])])]) -> Data {
    let results: [[String: Any]] = stations.map { station, destinations in
        [
            "consideredStation": station,
            "destinations": destinations.map { label, messages in
                [
                    "label": label,
                    "messages": messages.map { m in
                        [
                            "target": m.target,
                            "secondsToArrival": m.seconds,
                            "arrivalTimeMessage": "\(m.seconds) s",
                            "lineColor": m.color,
                            "headSign": m.headsign,
                            "lastUpdated": m.lastUpdated,
                        ]
                    },
                ] as [String: Any]
            },
        ]
    }
    return try! JSONSerialization.data(withJSONObject: ["results": results])
}

/// 2026-11-26T20:00:00-05:00
let feedBase = PATHDateParser.parse("2026-11-26T20:00:00-05:00")!

/// A request seen by `StubURLProtocol`.
struct RecordedRequest: Sendable {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data?

    /// Percent-decoded path, e.g. "/repos/yesh0907/PATH-stat/issues".
    var path: String { url.path(percentEncoded: false) }

    /// The JSON body as a dictionary.
    var json: [String: Any]? {
        body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// URLProtocol stub. Fixed responses are keyed by absolute URL; routed hosts
/// (`registerHost`) get a handler and record every request, one unique host per test, so
/// parallel tests don't collide.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Response: Sendable {
        case http(status: Int, body: Data)
        case httpWithHeaders(status: Int, headers: [String: String], body: Data)
        case failure(URLError.Code)
        /// Never responds, so the request stays in flight until it is cancelled.
        case hang

        static func json(_ status: Int, _ text: String = "{}", headers: [String: String] = [:]) -> Response {
            .httpWithHeaders(status: status, headers: headers, body: Data(text.utf8))
        }
    }

    typealias Route = @Sendable (RecordedRequest) -> Response

    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: Response] = [:]
    nonisolated(unsafe) private static var routes: [String: Route] = [:]
    nonisolated(unsafe) private static var recorded: [String: [RecordedRequest]] = [:]

    static func register(_ response: Response) -> URL {
        let url = URL(string: "https://stub.invalid/\(UUID().uuidString)")!
        lock.withLock { responses[url.absoluteString] = response }
        return url
    }

    /// A fresh base URL (`https://<uuid>.stub.invalid`) whose requests go to `route`.
    static func registerHost(_ route: @escaping Route) -> URL {
        let host = "\(UUID().uuidString.lowercased()).stub.invalid"
        lock.withLock { routes[host] = route }
        return URL(string: "https://\(host)")!
    }

    /// Requests sent to a `registerHost` base URL, in order.
    static func requests(to base: URL) -> [RecordedRequest] {
        lock.withLock { recorded[base.host() ?? ""] ?? [] }
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    override func startLoading() {
        let host = request.url?.host() ?? ""
        let response: Response?
        if let route = Self.lock.withLock({ Self.routes[host] }) {
            let recordedRequest = RecordedRequest(
                method: request.httpMethod ?? "GET",
                url: request.url!,
                headers: request.allHTTPHeaderFields ?? [:],
                body: Self.body(of: request)
            )
            Self.lock.withLock { Self.recorded[host, default: []].append(recordedRequest) }
            response = route(recordedRequest)
        } else {
            let key = request.url?.absoluteString ?? ""
            response = Self.lock.withLock { Self.responses[key] }
        }
        switch response {
        case .http(let status, let body):
            deliver(status: status, headers: nil, body: body)
        case .httpWithHeaders(let status, let headers, let body):
            deliver(status: status, headers: headers, body: body)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .hang:
            break
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
        }
    }

    private func deliver(status: Int, headers: [String: String]?, body: Data) {
        let http = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
