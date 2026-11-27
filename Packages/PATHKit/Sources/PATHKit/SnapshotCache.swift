import Foundation

/// Persists the latest feed snapshot as JSON so the widget (and the app on launch) can show
/// recent data without a network round trip.
public struct SnapshotCache: Sendable {
    public static let fileName = "latest-snapshot.json"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The App Group container (`TripStore.appGroupSuite`) when the entitlement is present,
    /// else the caches directory (e.g. in `swift test` or a build without the App Group).
    public static var shared: SnapshotCache {
        let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TripStore.appGroupSuite)
            ?? URL.cachesDirectory
        return SnapshotCache(directory: directory)
    }

    public var fileURL: URL { directory.appending(path: Self.fileName, directoryHint: .notDirectory) }

    /// Atomically replaces the cached snapshot. Failures are ignored: the cache is best-effort.
    public func save(_ snapshot: PATHSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// The cached snapshot, or nil if there is none or it can't be decoded.
    public func load() -> PATHSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PATHSnapshot.self, from: data)
    }
}
