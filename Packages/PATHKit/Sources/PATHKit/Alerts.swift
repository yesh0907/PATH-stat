import Foundation

/// A PATH service alert from the Everbridge incidents feed.
public struct ServiceAlert: Identifiable, Hashable, Sendable {
    public let id: String
    public let subject: String
    /// `preMessage`, trimmed of surrounding whitespace/newlines.
    public let message: String
    public let createdAt: Date
    public let modifiedAt: Date
    /// Raw line labels from the alert's "Lines" variable, e.g. `["HOB-WTC", "HOB-33"]`.
    public let lines: [String]
    /// Stations from the alert's "Station" variable that map to known codes.
    public let stations: [StationCode]

    public init(id: String, subject: String, message: String, createdAt: Date, modifiedAt: Date, lines: [String], stations: [StationCode]) {
        self.id = id
        self.subject = subject
        self.message = message
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.lines = lines
        self.stations = stations
    }
}
