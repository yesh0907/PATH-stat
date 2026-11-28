import Foundation

/// Persists favourite trips and the last trip in `UserDefaults` as JSON.
///
/// `suiteName` is the hook for sharing with a widget via an App Group later; nil uses
/// `UserDefaults.standard`. The defaults object is resolved per access so the store stays a
/// plain `Sendable` value.
public struct TripStore: Sendable {
    public let suiteName: String?

    static let favoritesKey = "PATHStat.favorites"
    static let lastTripKey = "PATHStat.lastTrip"
    static let lastNearestStationKey = "PATHStat.lastNearestStation"

    /// App Group shared by the app and its widget extension.
    public static let appGroupSuite = "group.com.yesh0907.PATHStat"

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    /// The App Group store when this process has the App Group entitlement (its container
    /// exists and `UserDefaults(suiteName:)` accepts it), else `UserDefaults.standard`.
    public static var shared: TripStore {
        let hasGroup = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupSuite) != nil
            && UserDefaults(suiteName: appGroupSuite) != nil
        return TripStore(suiteName: hasGroup ? appGroupSuite : nil)
    }

    /// One-time copy of favourites and the last trip from `legacy` (e.g. the pre-App Group
    /// standard defaults). Runs only while this store has never saved favourites; it then
    /// writes favourites (the legacy list, or the presets), so later calls do nothing.
    /// Never overwrites an existing last trip, and does nothing when both use the same suite.
    public func migrateIfNeeded(from legacy: TripStore) {
        guard legacy.suiteName != suiteName, !hasSavedFavorites else { return }
        favorites = legacy.favorites
        if lastTrip == nil, let legacyLast = legacy.lastTrip {
            lastTrip = legacyLast
        }
    }

    var hasSavedFavorites: Bool { defaults.object(forKey: Self.favoritesKey) != nil }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    /// Saved trips; `Trip.presets` until something has been saved (an empty list stays empty).
    public var favorites: [Trip] {
        get { decode([Trip].self, Self.favoritesKey) ?? Trip.presets }
        nonmutating set { encode(newValue, Self.favoritesKey) }
    }

    public var lastTrip: Trip? {
        get { decode(Trip.self, Self.lastTripKey) }
        nonmutating set {
            if let newValue { encode(newValue, Self.lastTripKey) } else { defaults.removeObject(forKey: Self.lastTripKey) }
        }
    }

    /// The last station a location fix put the rider nearest to. A station code only,
    /// never coordinates, so it is safe to share with the widget.
    public var lastNearestStation: StationCode? {
        get { defaults.string(forKey: Self.lastNearestStationKey).flatMap(StationCode.init(rawValue:)) }
        nonmutating set {
            if let newValue {
                defaults.set(newValue.rawValue, forKey: Self.lastNearestStationKey)
            } else {
                defaults.removeObject(forKey: Self.lastNearestStationKey)
            }
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
