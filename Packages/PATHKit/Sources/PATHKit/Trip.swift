import Foundation

/// A rider's journey: board at `origin`, ride to `destination`.
public struct Trip: Codable, Hashable, Sendable, Identifiable {
    public let origin: StationCode
    public let destination: StationCode
    /// Optional user-facing name, e.g. "Going home".
    public let name: String?

    public init(origin: StationCode, destination: StationCode, name: String? = nil) {
        self.origin = origin
        self.destination = destination
        self.name = name
    }

    public var id: String { "\(origin.rawValue)-\(destination.rawValue)" }

    /// `name`, or "Grove St → 33rd St".
    public var title: String {
        name ?? "\(StationCatalog.station(origin).shortName) → \(StationCatalog.station(destination).shortName)"
    }

    /// Whether this trip has the same origin and destination as `other`, ignoring the name.
    public func sameRoute(as other: Trip) -> Bool {
        origin == other.origin && destination == other.destination
    }

    public static let groveTo33rd = Trip(origin: .groveStreet, destination: .thirtyThirdStreet)
    public static let groveToWTC = Trip(origin: .groveStreet, destination: .worldTradeCenter)
    public static let goingHome = Trip(origin: .twentyThirdStreet, destination: .groveStreet, name: "Going home")

    public static let presets: [Trip] = [.groveTo33rd, .groveToWTC, .goingHome]

    /// The preset with this route if there is one (keeping its name), else an unnamed trip.
    public static func route(from origin: StationCode, to destination: StationCode) -> Trip {
        presets.first { $0.origin == origin && $0.destination == destination }
            ?? Trip(origin: origin, destination: destination)
    }
}

// MARK: - Deep links

extension Trip {
    public static let urlScheme = "pathstat"
    static let urlHost = "trip"

    /// `pathstat://trip?from=GRV&to=33S`, for widget / shortcut deep links.
    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.urlScheme
        components.host = Self.urlHost
        components.queryItems = [
            URLQueryItem(name: "from", value: origin.rawValue),
            URLQueryItem(name: "to", value: destination.rawValue),
        ]
        // Station codes are URL-safe, so this cannot fail.
        return components.url!
    }

    /// Parses `pathstat://trip?from=GRV&to=33S`. Rejects other schemes/hosts, unknown station
    /// codes, and routes no single line serves (including origin == destination). A route matching a preset gets the preset's name.
    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == Self.urlScheme,
              components.host?.lowercased() == Self.urlHost else { return nil }
        func code(_ name: String) -> StationCode? {
            components.queryItems?.first { $0.name == name }?.value
                .flatMap { StationCode(rawValue: $0.trimmingCharacters(in: .whitespaces).uppercased()) }
        }
        guard let from = code("from"), let to = code("to"),
              !StationCatalog.lines(serving: from, to: to).isEmpty else { return nil }
        self = Trip.route(from: from, to: to)
    }
}
