import CoreLocation
import Foundation

/// Direction of travel as labelled by the PATH realtime feed.
public enum Direction: String, Codable, CaseIterable, Sendable {
    case toNY = "ToNY"
    case toNJ = "ToNJ"
}

/// PATH station codes as used by the realtime feed's `consideredStation` / `target` fields.
public enum StationCode: String, Codable, CaseIterable, Sendable {
    case newark = "NWK"
    case harrison = "HAR"
    case journalSquare = "JSQ"
    case groveStreet = "GRV"
    case newport = "NEW"
    case exchangePlace = "EXP"
    case hoboken = "HOB"
    case worldTradeCenter = "WTC"
    case christopherStreet = "CHR"
    case ninthStreet = "09S"
    case fourteenthStreet = "14S"
    case twentyThirdStreet = "23S"
    case thirtyThirdStreet = "33S"
}

/// A PATH station with its location and the lines that serve it.
public struct Station: Identifiable, Hashable, Sendable {
    public let code: StationCode
    public let name: String
    /// Compact name for chips and titles, e.g. "Grove St", "Journal Sq", "WTC".
    public let shortName: String
    public let latitude: Double
    public let longitude: Double
    public let lines: [PATHLine]

    public var id: StationCode { code }

    public init(
        code: StationCode,
        name: String,
        shortName: String? = nil,
        latitude: Double,
        longitude: Double,
        lines: [PATHLine]
    ) {
        self.code = code
        self.name = name
        self.shortName = shortName ?? name
        self.latitude = latitude
        self.longitude = longitude
        self.lines = lines
    }

    public var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    /// Directions in which trains can depart this station, derived from line stop order.
    /// A station is a `toNY` departure point if it isn't the NY terminus of some line,
    /// and a `toNJ` departure point if it isn't the NJ terminus of some line.
    public var directions: Set<Direction> {
        var result = Set<Direction>()
        for line in lines {
            guard let index = line.stops.firstIndex(of: code) else { continue }
            if index < line.stops.count - 1 { result.insert(.toNY) }
            if index > 0 { result.insert(.toNJ) }
        }
        return result
    }
}

/// Static catalog of PATH stations.
public enum StationCatalog {
    private static let raw: [(StationCode, String, String, Double, Double)] = [
        (.newark, "Newark", "Newark", 40.73454, -74.16375),
        (.harrison, "Harrison", "Harrison", 40.73942, -74.15587),
        (.journalSquare, "Journal Square", "Journal Sq", 40.73301, -74.06289),
        (.groveStreet, "Grove Street", "Grove St", 40.71966, -74.04245),
        (.newport, "Newport", "Newport", 40.72699, -74.03383),
        (.exchangePlace, "Exchange Place", "Exchange Pl", 40.71676, -74.03238),
        (.hoboken, "Hoboken", "Hoboken", 40.73573, -74.02931),
        (.worldTradeCenter, "World Trade Center", "WTC", 40.71271, -74.01193),
        (.christopherStreet, "Christopher Street", "Christopher St", 40.73291, -74.00707),
        (.ninthStreet, "9th Street", "9th St", 40.73424, -73.99895),
        (.fourteenthStreet, "14th Street", "14th St", 40.73735, -73.99684),
        (.twentyThirdStreet, "23rd Street", "23rd St", 40.74291, -73.99266),
        (.thirtyThirdStreet, "33rd Street", "33rd St", 40.74885, -73.98820),
    ]

    public static let all: [Station] = raw.map { code, name, shortName, lat, lon in
        Station(
            code: code,
            name: name,
            shortName: shortName,
            latitude: lat,
            longitude: lon,
            lines: PATHLine.allCases.filter { $0.stops.contains(code) }
        )
    }

    private static let byCode: [StationCode: Station] = Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })

    public static func station(_ code: StationCode) -> Station {
        // Every StationCode case is present in `raw`; enforced by tests.
        byCode[code]!
    }

    /// All stations sorted by ascending distance from `location`.
    public static func stations(nearest location: CLLocation) -> [(station: Station, distance: CLLocationDistance)] {
        all.map { (station: $0, distance: $0.location.distance(from: location)) }
            .sorted { $0.distance < $1.distance }
    }

    /// Lines on which a rider can travel directly from `from` to `to`.
    public static func lines(serving from: StationCode, to: StationCode) -> [PATHLine] {
        guard from != to else { return [] }
        return PATHLine.allCases.filter { $0.stops.contains(from) && $0.stops.contains(to) }
    }

    /// Direction of travel from `from` to `to`, or nil if no single line connects them.
    /// Where lines disagree (e.g. Newport→Hoboken is ToNJ on Hoboken–WTC but ToNY on the
    /// via-Hoboken service) the first line in `PATHLine.allCases` order wins.
    public static func direction(from: StationCode, to: StationCode) -> Direction? {
        guard let line = lines(serving: from, to: to).first,
              let a = line.stops.firstIndex(of: from),
              let b = line.stops.firstIndex(of: to) else { return nil }
        return b > a ? .toNY : .toNJ
    }
}
