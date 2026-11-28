import Foundation
import Testing
@testable import PATHKit

struct TrainScheduleTests {
    @Test func calendarExceptionsAndDownstreamStops() throws {
        let schedule = try TrainSchedule(files: Self.files)
        let holiday = Self.instant("2026-11-27T18:55:00Z")
        #expect(schedule.nextDeparture(for: .groveToWTC, after: holiday) == Self.instant("2026-11-27T19:07:30Z"))
        #expect(schedule.nextDeparture(for: .groveTo33rd, after: holiday) == nil)
        #expect(schedule.nextDeparture(for: .route(from: .worldTradeCenter, to: .groveStreet), after: holiday) == nil)
        #expect(schedule.nextDeparture(for: .groveToWTC, after: Self.instant("2026-11-30T19:00:00Z")) == nil)
    }

    @Test func rollsPastExactDepartureAndChecksOverlappingServiceDays() throws {
        let schedule = try TrainSchedule(files: Self.files)
        #expect(schedule.nextDeparture(for: .groveToWTC, after: Self.instant("2026-11-27T19:07:30Z"))
            == Self.instant("2026-11-28T06:20:00Z"))
        #expect(schedule.nextDeparture(for: .groveToWTC, after: Self.instant("2026-11-28T06:20:00Z"))
            == Self.instant("2026-11-28T08:00:00Z"))
    }

    @Test func usesGTFSServiceDayClockAcrossDST() throws {
        let schedule = try TrainSchedule(files: Self.files)
        #expect(schedule.nextDeparture(for: .groveToWTC, after: Self.instant("2026-11-01T04:00:00Z"))
            == Self.instant("2026-11-01T06:20:00Z"))
    }

    @Test(arguments: [
        "UEsDBBQAAAAIAAAAIQDFZ/wYGQAAABcAAAAJAAAAc3RvcHMudHh0y0jNycnXUShOzkhNKc1JTVEoKUrMzFMEAFBLAQIUAxQAAAAIAAAAIQDFZ/wYGQAAABcAAAAJAAAAAAAAAAAAAACAAQAAAABzdG9wcy50eHRQSwUGAAAAAAEAAQA3AAAAQAAAAAAA",
        "UEsDBBQAAAAAAAAAIQDFZ/wYFwAAABcAAAAJAAAAc3RvcHMudHh0aGVsbG8sIHNjaGVkdWxlZCB0cmFpbiFQSwECFAMUAAAAAAAAACEAxWf8GBcAAAAXAAAACQAAAAAAAAAAAAAAgAEAAAAAc3RvcHMudHh0UEsFBgAAAAABAAEANwAAAD4AAAAAAA==",
    ])
    func extractsZIPAndRejectsTruncation(encoded: String) throws {
        let archive = try #require(Data(base64Encoded: encoded))
        #expect(try ScheduleZIP.extract(archive, names: ["stops.txt"]) == ["stops.txt": Data("hello, scheduled train!".utf8)])
        #expect(throws: ScheduleError.self) {
            _ = try ScheduleZIP.extract(archive.dropLast(), names: ["stops.txt"])
        }
    }

    static func instant(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    static let files = [
        "stops.txt": """
        stop_id,stop_name,parent_station
        place_GRV,Grove Street,
        grv,"Grove, eastbound",place_GRV
        wtc,"World Trade Center",
        33rd,33rd Street,
        """,
        "calendar.txt": """
        service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date
        usual,0,0,0,0,1,0,0,20261127,20261127
        """,
        "calendar_dates.txt": """
        service_id,date,exception_type
        usual,20261127,2
        special,20261127,1
        special,20261128,1
        special,20261101,1
        """,
        "trips.txt": """
        trip_id,service_id
        normal,usual
        holiday,special
        overnight,special
        early,special
        skip,special
        """,
        "stop_times.txt": """
        trip_id,stop_id,stop_sequence,departure_time,pickup_type,drop_off_type
        normal,grv,1,14:01:00,,
        normal,wtc,2,14:11:00,,
        holiday,wtc,30,14:17:30,,
        holiday,grv,10,14:07:30,,
        overnight,grv,1,27:00:00,,
        overnight,wtc,2,27:10:00,,
        early,grv,1,1:20:00,,
        early,wtc,2,1:30:00,,
        skip,grv,1,14:00:00,1,
        skip,wtc,2,14:10:00,,
        skip,33rd,3,14:19:00,,1
        """,
    ].mapValues { Data($0.utf8) }
}
