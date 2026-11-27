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

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

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

    private func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
