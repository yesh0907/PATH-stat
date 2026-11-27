import CoreLocation
import Foundation
import Testing
@testable import PATHKit

@Suite("StationCatalog")
struct CatalogTests {
    @Test func thirteenUniqueStations() {
        #expect(StationCatalog.all.count == 13)
        #expect(Set(StationCatalog.all.map(\.code)) == Set(StationCode.allCases))
        for code in StationCode.allCases {
            #expect(StationCatalog.station(code).id == code)
        }
        #expect(StationCatalog.station(.groveStreet).name == "Grove Street")
        #expect(StationCatalog.station(.ninthStreet).name == "9th Street")
    }

    @Test func everyLineStopExistsAndIsUnique() {
        let codes = Set(StationCatalog.all.map(\.code))
        for line in PATHLine.allCases {
            #expect(line.stops.allSatisfy(codes.contains))
            #expect(Set(line.stops).count == line.stops.count)
            #expect(line.stops.count >= 2)
            for stop in line.stops {
                #expect(StationCatalog.station(stop).lines.contains(line))
            }
        }
        #expect(StationCatalog.all.allSatisfy { !$0.lines.isEmpty })
    }

    @Test func stationDirections() {
        #expect(StationCatalog.station(.newark).directions == [.toNY])
        #expect(StationCatalog.station(.worldTradeCenter).directions == [.toNJ])
        #expect(StationCatalog.station(.thirtyThirdStreet).directions == [.toNJ])
        #expect(StationCatalog.station(.hoboken).directions == [.toNY, .toNJ])
        #expect(StationCatalog.station(.groveStreet).directions == [.toNY, .toNJ])
        #expect(StationCatalog.station(.journalSquare).directions == [.toNY, .toNJ])
    }

    @Test func nearestGroveStreet() throws {
        let grove = StationCatalog.station(.groveStreet).location
        let result = StationCatalog.stations(nearest: grove)
        #expect(result.count == 13)
        #expect(result.first?.station.code == .groveStreet)
        #expect(try #require(result.first).distance < 1)
        #expect(result.map(\.distance) == result.map(\.distance).sorted())
    }

    @Test func nearestMidtownIsThirtyThird() {
        // 34th St & 6th Ave, Herald Square.
        let midtown = CLLocation(latitude: 40.74967, longitude: -73.98794)
        let result = StationCatalog.stations(nearest: midtown)
        #expect(result.first?.station.code == .thirtyThirdStreet)
        #expect(result.dropFirst().first?.station.code == .twentyThirdStreet)
        #expect(zip(result, result.dropFirst()).allSatisfy { $0.distance <= $1.distance })
        #expect(result.last?.station.code == .newark)
    }

    @Test func linesAndDirectionBetweenStations() {
        #expect(StationCatalog.lines(serving: .groveStreet, to: .thirtyThirdStreet) == [.journalSquare33rd, .journalSquare33rdViaHoboken])
        #expect(StationCatalog.lines(serving: .groveStreet, to: .worldTradeCenter) == [.newarkWTC])
        #expect(StationCatalog.lines(serving: .newark, to: .hoboken).isEmpty)
        #expect(StationCatalog.lines(serving: .groveStreet, to: .groveStreet).isEmpty)
        #expect(StationCatalog.direction(from: .groveStreet, to: .thirtyThirdStreet) == .toNY)
        #expect(StationCatalog.direction(from: .twentyThirdStreet, to: .groveStreet) == .toNJ)
        #expect(StationCatalog.direction(from: .worldTradeCenter, to: .newark) == .toNJ)
        #expect(StationCatalog.direction(from: .hoboken, to: .worldTradeCenter) == .toNY)
        #expect(StationCatalog.direction(from: .newark, to: .hoboken) == nil)
        #expect(StationCatalog.direction(from: .groveStreet, to: .groveStreet) == nil)
    }

    @Test func lineIdentification() {
        #expect(PATHLine.identify(lineColor: "D93A30", target: .worldTradeCenter) == .newarkWTC)
        #expect(PATHLine.identify(lineColor: "65c100", target: nil) == .hobokenWTC)
        #expect(PATHLine.identify(lineColor: "#FF9900", target: .thirtyThirdStreet) == .journalSquare33rd)
        #expect(PATHLine.identify(lineColor: "4D92FB", target: .hoboken) == .hoboken33rd)
        #expect(PATHLine.identify(lineColor: "4D92FB,FF9900", target: .thirtyThirdStreet) == .journalSquare33rdViaHoboken)
        #expect(PATHLine.identify(lineColor: "FF9900, 4D92FB", target: .journalSquare) == .journalSquare33rdViaHoboken)
        #expect(PATHLine.identify(lineColor: "", target: .hoboken) == nil)
        #expect(PATHLine.identify(lineColor: "000000", target: .hoboken) == nil)
        for line in PATHLine.allCases {
            #expect(PATHLine.identify(lineColor: line.colorHex, target: nil) == line)
            #expect(!line.displayName.isEmpty)
        }
    }
}
