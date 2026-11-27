import Foundation

/// What kind of feedback a report is. `label` is the GitHub issue label.
public enum FeedbackCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case bug
    case designNit = "design-nit"
    case frustration
    case idea

    public var id: String { rawValue }

    /// The GitHub label for this category (alongside `FeedbackIssueFormatter.feedbackLabel`).
    public var label: String { rawValue }

    public var title: String {
        switch self {
        case .bug: "Bug"
        case .designNit: "Design nit"
        case .frustration: "Frustration"
        case .idea: "Idea"
        }
    }
}

/// App state captured when the feedback sheet opens. Deliberately coarse: never coordinates,
/// distances or anything else location-derived beyond the station header's context word.
public struct FeedbackContext: Codable, Hashable, Sendable {
    public var appVersion: String
    /// Short git commit the build came from, `-dirty` when built with local changes.
    public var gitCommit: String?
    public var osVersion: String
    public var deviceModel: String
    /// Which screen was showing, e.g. "main" or "station picker".
    public var screen: String
    /// "Grove St → 33rd St (GRV → 33S)".
    public var trip: String?
    /// Only "nearest", "home station" or "selected".
    public var stationContext: String?
    /// Only "authorized", "denied" or "not determined".
    public var locationPermission: String?
    public var feedFetchedAt: Date?
    public var feedAgeSeconds: Int?
    /// "fresh", "stale" or "unknown".
    public var feedFreshness: String?
    public var lastFeedError: String?
    /// `RecentNotices.descriptions`, oldest first.
    public var recentNotices: [String]
    public var liveActivity: String?
    /// "light" / "dark".
    public var appearance: String
    public var dynamicTypeSize: String
    public var timestamp: Date

    public init(
        appVersion: String,
        gitCommit: String? = nil,
        osVersion: String,
        deviceModel: String,
        screen: String,
        trip: String? = nil,
        stationContext: String? = nil,
        locationPermission: String? = nil,
        feedFetchedAt: Date? = nil,
        feedAgeSeconds: Int? = nil,
        feedFreshness: String? = nil,
        lastFeedError: String? = nil,
        recentNotices: [String] = [],
        liveActivity: String? = nil,
        appearance: String,
        dynamicTypeSize: String,
        timestamp: Date
    ) {
        self.appVersion = appVersion
        self.gitCommit = gitCommit
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.screen = screen
        self.trip = trip
        self.stationContext = stationContext
        self.locationPermission = locationPermission
        self.feedFetchedAt = feedFetchedAt
        self.feedAgeSeconds = feedAgeSeconds
        self.feedFreshness = feedFreshness
        self.lastFeedError = lastFeedError
        self.recentNotices = recentNotices
        self.liveActivity = liveActivity
        self.appearance = appearance
        self.dynamicTypeSize = dynamicTypeSize
        self.timestamp = timestamp
    }

    /// "Grove St → 33rd St (GRV → 33S)".
    public static func tripDescription(_ trip: Trip) -> String {
        "\(trip.title) (\(trip.origin.rawValue) → \(trip.destination.rawValue))"
    }
}

/// One piece of feedback, as written by the user.
public struct FeedbackReport: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var note: String
    public var category: FeedbackCategory
    public var context: FeedbackContext
    public var createdAt: Date

    public init(id: UUID = UUID(), note: String, category: FeedbackCategory, context: FeedbackContext, createdAt: Date = .now) {
        self.id = id
        self.note = note
        self.category = category
        self.context = context
        self.createdAt = createdAt
    }
}

/// The last few user-visible problems (offline banner, stale data, …), for feedback context.
public struct RecentNotices: Hashable, Sendable {
    public struct Notice: Hashable, Sendable {
        public let text: String
        public let date: Date
    }

    public static let capacity = 5
    /// The same text as the newest notice within this window is not recorded again.
    public static let repeatWindow: TimeInterval = 60

    /// Oldest first.
    public private(set) var notices: [Notice] = []
    public var timeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    public mutating func record(_ text: String, at date: Date = .now) {
        if let newest = notices.last, newest.text == text,
           abs(date.timeIntervalSince(newest.date)) < Self.repeatWindow { return }
        notices.append(Notice(text: text, date: date))
        if notices.count > Self.capacity { notices.removeFirst(notices.count - Self.capacity) }
    }

    /// "20:41:07 Can't reach PATH", newest last.
    public var descriptions: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss"
        return notices.map { "\(formatter.string(from: $0.date)) \($0.text)" }
    }
}
