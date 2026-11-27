import Foundation

/// PATH service patterns.
public enum PATHLine: String, CaseIterable, Sendable {
    case newarkWTC
    case hobokenWTC
    case journalSquare33rd
    case hoboken33rd
    case journalSquare33rdViaHoboken

    public var displayName: String {
        switch self {
        case .newarkWTC: "Newark–WTC"
        case .hobokenWTC: "Hoboken–WTC"
        case .journalSquare33rd: "Journal Square–33rd St"
        case .hoboken33rd: "Hoboken–33rd St"
        case .journalSquare33rdViaHoboken: "Journal Square–33rd St via Hoboken"
        }
    }

    /// Line colour as it appears in the feed's `lineColor` field (may be a comma list).
    public var colorHex: String {
        switch self {
        case .newarkWTC: "D93A30"
        case .hobokenWTC: "65C100"
        case .journalSquare33rd: "FF9900"
        case .hoboken33rd: "4D92FB"
        case .journalSquare33rdViaHoboken: "4D92FB,FF9900"
        }
    }

    /// Stops in order from the New Jersey end to the New York end.
    public var stops: [StationCode] {
        switch self {
        case .newarkWTC: [.newark, .harrison, .journalSquare, .groveStreet, .exchangePlace, .worldTradeCenter]
        case .hobokenWTC: [.hoboken, .newport, .exchangePlace, .worldTradeCenter]
        case .journalSquare33rd:
            [.journalSquare, .groveStreet, .newport, .christopherStreet, .ninthStreet,
             .fourteenthStreet, .twentyThirdStreet, .thirtyThirdStreet]
        case .hoboken33rd:
            [.hoboken, .christopherStreet, .ninthStreet, .fourteenthStreet, .twentyThirdStreet, .thirtyThirdStreet]
        case .journalSquare33rdViaHoboken:
            [.journalSquare, .groveStreet, .newport, .hoboken, .christopherStreet, .ninthStreet,
             .fourteenthStreet, .twentyThirdStreet, .thirtyThirdStreet]
        }
    }

    /// Normalised colour set (upper-cased, `#` stripped, order-insensitive).
    static func colorSet(_ value: String) -> Set<String> {
        Set(
            value.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "").uppercased() }
                .filter { !$0.isEmpty }
        )
    }

    private static let byColor: [Set<String>: PATHLine] = Dictionary(
        uniqueKeysWithValues: allCases.map { (colorSet($0.colorHex), $0) }
    )

    /// Identifies a line from the feed's `lineColor` (single hex or comma list, order-insensitive).
    /// Returns nil for an empty or unrecognised colour.
    public static func identify(lineColor: String) -> PATHLine? {
        byColor[colorSet(lineColor)]
    }
}
