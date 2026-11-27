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

/// URLProtocol stub keyed by absolute URL so parallel tests don't collide.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Response: Sendable {
        case http(status: Int, body: Data)
        case failure(URLError.Code)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: Response] = [:]

    static func register(_ response: Response) -> URL {
        let url = URL(string: "https://stub.invalid/\(UUID().uuidString)")!
        lock.withLock { responses[url.absoluteString] = response }
        return url
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = request.url?.absoluteString ?? ""
        let response = Self.lock.withLock { Self.responses[key] }
        switch response {
        case .http(let status, let body):
            let http = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
        }
    }

    override func stopLoading() {}
}
