import Foundation

/// Fetches and parses the PATH realtime arrivals feed and service alerts.
public struct PATHClient: Sendable {
    public static let defaultFeedURL = URL(string: "https://www.panynj.gov/bin/portauthority/ridepath.json")!
    public static let defaultAlertsURL = URL(
        string: "https://www.panynj.gov/bin/portauthority/everbridge/incidents?status=All&department=Path"
    )!
    public static let requestTimeout: TimeInterval = 15

    public let session: URLSession
    public let feedURL: URL
    public let alertsURL: URL
    public let now: @Sendable () -> Date

    public init(
        session: URLSession = .shared,
        feedURL: URL = PATHClient.defaultFeedURL,
        alertsURL: URL = PATHClient.defaultAlertsURL,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.session = session
        self.feedURL = feedURL
        self.alertsURL = alertsURL
        self.now = now
    }

    // MARK: Fetching

    public func fetchSnapshot() async throws -> PATHSnapshot {
        let data = try await get(feedURL)
        return try Self.parseSnapshot(data, fetchedAt: now())
    }

    public func departures(
        at station: StationCode,
        direction: Direction,
        toward: StationCode? = nil,
        headsign: String? = nil
    ) async throws -> DepartureBoard {
        try await fetchSnapshot().departures(at: station, direction: direction, toward: toward, headsign: headsign, now: now())
    }

    public func fetchAlerts() async throws -> [ServiceAlert] {
        try Self.parseAlerts(try await get(alertsURL))
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.requestTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw PATHError.from(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PATHError.invalidResponse("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw PATHError.httpStatus(http.statusCode)
        }
        return data
    }

    // MARK: Realtime feed parsing

    private struct FeedDTO: Decodable {
        let results: [ResultDTO]?
    }
    private struct ResultDTO: Decodable {
        let consideredStation: String?
        let destinations: [DestinationDTO]?
    }
    private struct DestinationDTO: Decodable {
        let label: String?
        let messages: [MessageDTO]?
    }
    private struct MessageDTO: Decodable {
        let target: String?
        let secondsToArrival: String?
        let arrivalTimeMessage: String?
        let lineColor: String?
        let headSign: String?
        let lastUpdated: String?
    }

    /// Parses the `ridepath.json` payload. Unknown stations, labels, and malformed
    /// messages are skipped; non-JSON or a missing `results` array throws `.invalidResponse`.
    public static func parseSnapshot(_ data: Data, fetchedAt: Date) throws -> PATHSnapshot {
        let feed: FeedDTO
        do {
            feed = try JSONDecoder().decode(FeedDTO.self, from: data)
        } catch {
            throw PATHError.invalidResponse("malformed realtime JSON")
        }
        guard let results = feed.results else {
            throw PATHError.invalidResponse("missing results")
        }

        var boards: [StationCode: [Direction: [TrainArrival]]] = [:]
        var seenIDs: [String: Int] = [:]
        for result in results {
            guard let raw = result.consideredStation, let station = StationCode(rawValue: raw) else { continue }
            for destination in result.destinations ?? [] {
                guard let label = destination.label, let direction = Direction(rawValue: label) else { continue }
                var trains = boards[station]?[direction] ?? []
                for message in destination.messages ?? [] {
                    guard let arrival = makeArrival(message, station: station, direction: direction) else { continue }
                    let duplicates = seenIDs[arrival.id, default: 0]
                    seenIDs[arrival.id] = duplicates + 1
                    trains.append(duplicates == 0 ? arrival : arrival.withID("\(arrival.id)#\(duplicates)"))
                }
                trains.sort { $0.arrival < $1.arrival }
                boards[station, default: [:]][direction] = trains
            }
        }
        return PATHSnapshot(fetchedAt: fetchedAt, boards: boards)
    }

    private static func makeArrival(_ m: MessageDTO, station: StationCode, direction: Direction) -> TrainArrival? {
        guard let secondsText = m.secondsToArrival?.trimmingCharacters(in: .whitespaces),
              let seconds = Double(secondsText), seconds.isFinite,
              let updatedText = m.lastUpdated,
              let lastUpdated = PATHDateParser.parse(updatedText) else { return nil }
        let target = m.target.flatMap { StationCode(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
        let colorText = m.lineColor ?? ""
        let colors = colorText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "").uppercased() }
            .filter { !$0.isEmpty }
        return TrainArrival(
            station: station,
            direction: direction,
            target: target,
            headsign: m.headSign?.trimmingCharacters(in: .whitespaces) ?? "",
            line: PATHLine.identify(lineColor: colorText),
            lineColors: colors,
            arrival: lastUpdated.addingTimeInterval(seconds),
            arrivalTimeMessage: m.arrivalTimeMessage ?? "",
            lastUpdated: lastUpdated
        )
    }

    // MARK: Alerts parsing

    private struct AlertsDTO: Decodable {
        let status: String?
        let data: [IncidentDTO]?
    }
    private struct IncidentDTO: Decodable {
        let incidentMessage: IncidentMessageDTO?
        let CreatedDate: String?
        let ModifiedDate: String?
    }
    private struct IncidentMessageDTO: Decodable {
        let subject: String?
        let preMessage: String?
        let formVariableItems: [VariableDTO]?
    }
    private struct VariableDTO: Decodable {
        let variableName: String?
        let val: [String]?
    }

    /// Alert station labels that differ from realtime feed codes.
    private static let alertStationAliases: [String: StationCode] = [
        "NWPT": .newport, "EXPL": .exchangePlace, "9ST": .ninthStreet, "9TH": .ninthStreet,
        "14ST": .fourteenthStreet, "14TH": .fourteenthStreet, "23ST": .twentyThirdStreet,
        "23RD": .twentyThirdStreet, "33ST": .thirtyThirdStreet, "33RD": .thirtyThirdStreet,
    ]

    /// Parses the Everbridge incidents payload, newest-modified first.
    public static func parseAlerts(_ data: Data) throws -> [ServiceAlert] {
        let payload: AlertsDTO
        do {
            payload = try JSONDecoder().decode(AlertsDTO.self, from: data)
        } catch {
            throw PATHError.invalidResponse("malformed alerts JSON")
        }
        guard let incidents = payload.data else {
            throw PATHError.invalidResponse("missing alerts data")
        }
        let alerts: [ServiceAlert] = incidents.compactMap { incident in
            guard let message = incident.incidentMessage else { return nil }
            let created = epochMillis(incident.CreatedDate)
            let modified = epochMillis(incident.ModifiedDate)
            guard let createdAt = created ?? modified else { return nil }
            let variables = message.formVariableItems ?? []
            func values(_ name: String) -> [String] {
                variables.filter { $0.variableName == name }.flatMap { $0.val ?? [] }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
            let stations = values("Station").compactMap { label -> StationCode? in
                let key = label.uppercased()
                return StationCode(rawValue: key) ?? alertStationAliases[key]
            }
            let subject = message.subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return ServiceAlert(
                id: "\(incident.CreatedDate ?? "")-\(subject)",
                subject: subject,
                message: message.preMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                createdAt: createdAt,
                modifiedAt: modified ?? createdAt,
                lines: values("Lines"),
                stations: stations
            )
        }
        return alerts.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private static func epochMillis(_ text: String?) -> Date? {
        guard let text, let ms = Double(text.trimmingCharacters(in: .whitespaces)), ms.isFinite else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }
}
