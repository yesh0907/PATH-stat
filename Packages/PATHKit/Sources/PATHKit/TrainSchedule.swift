import Foundation

enum ScheduleError: Error {
    case invalidArchive
    case invalidTable(String)
    case emptySchedule
}

/// A published timetable. It does not predict actual service.
public struct TrainSchedule: Sendable {
    private struct Route: Hashable, Sendable {
        let from: StationCode
        let to: StationCode
    }

    private struct Service: Sendable {
        var weekdays: Set<Int> = []
        var start = 0
        var end = 0
        var exceptions: [Int: Bool] = [:]

        var firstDay: Int { min(start == 0 ? Int.max : start, exceptions.keys.min() ?? Int.max) }
        var lastDay: Int { max(end, exceptions.keys.max() ?? 0) }

        func runs(on day: Int, weekday: Int) -> Bool {
            exceptions[day] ?? (day >= start && day <= end && weekdays.contains(weekday))
        }
    }

    private struct Stop {
        let station: StationCode
        let sequence: Int
        let departure: Int?
        let canExit: Bool
    }

    private static let tables: Set<String> = ["stops.txt", "trips.txt", "stop_times.txt", "calendar.txt", "calendar_dates.txt"]
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private let departures: [Route: [String: [Int]]]
    private let services: [String: Service]

    private init(departures: [Route: [String: [Int]]], services: [String: Service]) {
        self.departures = departures
        self.services = services
    }

    public init(gtfsZIP: Data) throws {
        try self.init(files: ScheduleZIP.extract(gtfsZIP, names: Self.tables))
    }

    init(files: [String: Data]) throws {
        func read(_ name: String, _ columns: [String], optional: [String] = [], required: Bool = true) throws -> [[String]] {
            guard let data = files[name] else {
                if !required { return [] }
                throw ScheduleError.invalidTable(name)
            }
            guard let text = String(data: data, encoding: .utf8) else { throw ScheduleError.invalidTable(name) }
            let lines = text.split(whereSeparator: \.isNewline)
            guard let first = lines.first else { throw ScheduleError.invalidTable(name) }
            let header = Self.fields(first).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}")) }
            guard columns.allSatisfy(header.contains) else { throw ScheduleError.invalidTable(name) }
            let positions = (columns + optional).map { header.firstIndex(of: $0) }
            return lines.dropFirst().compactMap { line in
                let row = Self.fields(line)
                guard row.count == header.count else { return nil }
                return positions.map { $0.map { row[$0] } ?? "" }
            }
        }

        let stationNames = Dictionary(uniqueKeysWithValues: StationCatalog.all.map { ($0.name.lowercased(), $0.code) })
        let stopRows = try read("stops.txt", ["stop_id", "stop_name"], optional: ["parent_station", "stop_code"])
        var stations: [String: StationCode] = [:]
        for row in stopRows {
            stations[row[0]] = Self.placeCode(row[0]) ?? StationCode(rawValue: row[3]) ?? stationNames[row[1].lowercased()]
        }
        for row in stopRows where !row[2].isEmpty {
            stations[row[0]] = stations[row[2]] ?? stations[row[0]]
        }

        var services: [String: Service] = [:]
        let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        for row in try read("calendar.txt", ["service_id", "start_date", "end_date"] + weekdays, required: false) {
            guard let start = Self.day(row[1]), let end = Self.day(row[2]), start <= end else { continue }
            let active = Set(weekdays.indices.filter { row[$0 + 3] == "1" }.map { $0 + 1 })
            services[row[0]] = Service(weekdays: active, start: start, end: end)
        }
        for row in try read("calendar_dates.txt", ["service_id", "date", "exception_type"], required: false) {
            guard let day = Self.day(row[1]), row[2] == "1" || row[2] == "2" else { continue }
            services[row[0], default: Service()].exceptions[day] = row[2] == "1"
        }

        var tripServices: [String: String] = [:]
        for row in try read("trips.txt", ["trip_id", "service_id"]) where services[row[1]] != nil {
            tripServices[row[0]] = row[1]
        }
        var stopsByTrip: [String: [Stop]] = [:]
        for row in try read("stop_times.txt", ["trip_id", "stop_id", "stop_sequence", "departure_time"],
                            optional: ["pickup_type", "drop_off_type"]) {
            guard tripServices[row[0]] != nil, let station = stations[row[1]], let sequence = Int(row[2]) else { continue }
            stopsByTrip[row[0], default: []].append(Stop(
                station: station, sequence: sequence, departure: row[4] == "1" ? nil : Self.seconds(row[3]),
                canExit: row[5] != "1"
            ))
        }
        var index: [Route: [String: Set<Int>]] = [:]
        for (trip, stops) in stopsByTrip {
            guard let service = tripServices[trip] else { continue }
            var downstream: Set<StationCode> = []
            for stop in stops.sorted(by: { $0.sequence > $1.sequence }) {
                if let time = stop.departure {
                    for destination in downstream where destination != stop.station {
                        let route = Route(from: stop.station, to: destination)
                        index[route, default: [:]][service, default: []].insert(time)
                    }
                }
                if stop.canExit { downstream.insert(stop.station) }
            }
        }
        guard !index.isEmpty else { throw ScheduleError.emptySchedule }
        self.init(departures: index.mapValues { $0.mapValues { $0.sorted() } }, services: services)
    }

    public func nextDeparture(for trip: Trip, after now: Date) -> Date? {
        guard let byService = departures[Route(from: trip.origin, to: trip.destination)] else { return nil }
        let calendar = Self.calendar
        let today = calendar.startOfDay(for: now)
        var best: Date?
        for (id, times) in byService {
            guard let service = services[id], let first = times.first, let last = times.last,
                  var date = calendar.date(byAdding: .day, value: -(last / 86_400 + 1), to: today)
            else { continue }
            let start = service.firstDay
            guard let firstDate = calendar.date(from: DateComponents(
                year: start / 10_000, month: start / 100 % 100, day: start % 100
            )) else { continue }
            date = max(date, firstDate)
            let end = service.lastDay
            while true {
                let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
                let day = parts.year! * 10_000 + parts.month! * 100 + parts.day!
                if day > end { break }
                // GTFS measures elapsed seconds from service-day noon minus 12 hours.
                let base = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!.addingTimeInterval(-43_200)
                if let best, base.addingTimeInterval(Double(first)) >= best { break }
                if service.runs(on: day, weekday: parts.weekday!),
                   let seconds = Self.firstTime(in: times, after: now.timeIntervalSince(base)) {
                    let departure = base.addingTimeInterval(Double(seconds))
                    if best.map({ departure < $0 }) ?? true { best = departure }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
                date = next
            }
        }
        return best
    }

    private static func firstTime(in sorted: [Int], after cutoff: TimeInterval) -> Int? {
        var lo = 0
        var hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if Double(sorted[mid]) <= cutoff { lo = mid + 1 } else { hi = mid }
        }
        return lo < sorted.count ? sorted[lo] : nil
    }

    private static func day(_ value: String) -> Int? {
        guard value.count == 8, let day = Int(value), (19000101...21991231).contains(day) else { return nil }
        return day
    }

    private static func placeCode(_ id: String) -> StationCode? {
        guard id.hasPrefix("place_") else { return nil }
        return StationCode(rawValue: String(id.dropFirst(6)))
    }

    private static func seconds(_ value: String) -> Int? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, let hour = Int(parts[0]), let minute = Int(parts[1]), let second = Int(parts[2]),
              (0...99).contains(hour), (0...59).contains(minute), (0...59).contains(second)
        else { return nil }
        return hour * 3_600 + minute * 60 + second
    }

    private static func fields(_ line: Substring) -> [String] {
        if !line.contains("\"") { return line.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        var fields: [String] = []
        var field = ""
        var quoted = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            line.formIndex(after: &index)
            switch character {
            case "\"" where quoted && index < line.endIndex && line[index] == "\"":
                field.append(character)
                line.formIndex(after: &index)
            case "\"":
                quoted.toggle()
            case "," where !quoted:
                fields.append(field)
                field = ""
            default:
                field.append(character)
            }
        }
        fields.append(field)
        return fields
    }
}

extension TrainSchedule {
    /// A timetable for scenario mode, with one departure approximately nine minutes out.
    public static func sample(now: Date) -> TrainSchedule {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)!
        let parts = calendar.dateComponents([.year, .month, .day], from: noon)
        let day = parts.year! * 10_000 + parts.month! * 100 + parts.day!
        let seconds = Int(now.timeIntervalSince(noon.addingTimeInterval(-43_200))) + 540
        let route = Route(from: .groveStreet, to: .worldTradeCenter)
        return TrainSchedule(
            departures: [route: ["sample": [seconds, seconds + 720]]],
            services: ["sample": Service(exceptions: [day: true])]
        )
    }
}
