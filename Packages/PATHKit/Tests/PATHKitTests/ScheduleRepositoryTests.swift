import Foundation
import Testing
@testable import PATHKit

struct ScheduleRepositoryTests {
    @Test func reusesValidCacheWhenFreshOrWhenRefreshFails() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = Self.storedZIP(TrainScheduleTests.files)
        let now = Date.now
        let repo = ScheduleRepository(directory: directory, fetch: { archive })
        let departure = TrainScheduleTests.instant("2026-11-27T19:07:30Z")
        let before = TrainScheduleTests.instant("2026-11-27T18:55:00Z")
        let first = await repo.refresh(now: now)
        #expect(first?.nextDeparture(for: .groveToWTC, after: before) == departure)

        let failing = ScheduleRepository(directory: directory) {
            Data("invalid ZIP".utf8)
        }
        let fresh = await failing.refresh(now: now.addingTimeInterval(60))
        let stale = await failing.refresh(now: now.addingTimeInterval(90_000))
        #expect(fresh?.nextDeparture(for: .groveToWTC, after: before) == departure)
        #expect(stale?.nextDeparture(for: .groveToWTC, after: before) == departure)
        #expect(try Data(contentsOf: directory.appending(path: "path-schedule.zip")) == archive)
    }

    private static func storedZIP(_ files: [String: Data]) -> Data {
        var archive = Data()
        var directory = Data()
        for (file, bytes) in files {
            let name = Data(file.utf8)
            let offset = archive.count
            archive += fields([(0x04034b50, 4), (20, 2), (0, 12), (bytes.count, 4),
                               (bytes.count, 4), (name.count, 2), (0, 2)])
            archive += name + bytes
            directory += fields([(0x02014b50, 4), (20, 2), (20, 2), (0, 12), (bytes.count, 4),
                                 (bytes.count, 4), (name.count, 2), (0, 12), (offset, 4)])
            directory += name
        }
        let end = fields([(0x06054b50, 4), (0, 4), (files.count, 2), (files.count, 2),
                          (directory.count, 4), (archive.count, 4), (0, 2)])
        return archive + directory + end
    }

    private static func fields(_ fields: [(value: Int, width: Int)]) -> Data {
        Data(fields.flatMap { field in (0..<field.width).map { UInt8(truncatingIfNeeded: field.value >> (8 * $0)) } })
    }
}
