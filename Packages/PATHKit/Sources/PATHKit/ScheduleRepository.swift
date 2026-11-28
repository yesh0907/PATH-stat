import Foundation

/// Keeps the last valid PATH timetable in the shared cache, independently of realtime arrivals.
public actor ScheduleRepository {
    public static let sourceURL = URL(string: "https://www.panynj.gov/content/dam/path/gtfs/PATH_GTFS.zip")!

    private let fileURL: URL
    private let fetch: @Sendable () async throws -> Data
    private var schedule: TrainSchedule?
    private var loadedCache = false
    private var lastSuccess: Date?
    private var lastAttempt: Date?
    private var inFlight: Task<TrainSchedule?, Never>?

    public init(
        directory: URL = SnapshotCache.shared.directory,
        fetch: (@Sendable () async throws -> Data)? = nil
    ) {
        fileURL = directory.appending(path: "path-schedule.zip", directoryHint: .notDirectory)
        self.fetch = fetch ?? { try await ScheduleRepository.download() }
    }

    static func download() async throws -> Data {
        let request = URLRequest(url: sourceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    public func cachedSchedule() -> TrainSchedule? {
        if !loadedCache {
            loadedCache = true
            if let bytes = try? Data(contentsOf: fileURL), let cached = try? TrainSchedule(gtfsZIP: bytes) {
                schedule = cached
                lastSuccess = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            }
        }
        return schedule
    }

    public func refresh(now: Date = .now) async -> TrainSchedule? {
        if let inFlight { return await inFlight.value }
        let cached = cachedSchedule()
        if let lastSuccess, (0..<86_400).contains(now.timeIntervalSince(lastSuccess)) { return cached }
        if let lastAttempt, (0..<900).contains(now.timeIntervalSince(lastAttempt)) { return cached }
        lastAttempt = now
        let task = Task<TrainSchedule?, Never> {
            defer { inFlight = nil }
            do {
                let bytes = try await fetch()
                let parsed = try TrainSchedule(gtfsZIP: bytes)
                schedule = parsed
                lastSuccess = now
                try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? bytes.write(to: fileURL, options: .atomic)
                return parsed
            } catch {
                return cached
            }
        }
        inFlight = task
        return await task.value
    }
}
