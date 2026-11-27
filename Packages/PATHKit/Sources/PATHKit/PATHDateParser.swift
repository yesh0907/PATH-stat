import Foundation

/// Parses the feed's ISO-8601 timestamps, e.g. `2026-11-26T20:44:07.263779-05:00`.
///
/// Accepts any number of fractional-second digits (or none) and an offset of `Z`,
/// `±HH:MM`, `±HHMM` or `±HH`. A missing offset is interpreted as PATH local time
/// (America/New_York). Implemented by hand because `ISO8601DateFormatter`
/// only reliably handles millisecond fractions.
public enum PATHDateParser {
    static let pathTimeZone = TimeZone(identifier: "America/New_York")!

    public static func parse(_ string: String) -> Date? {
        let s = Array(string.trimmingCharacters(in: .whitespaces).utf8)
        var i = 0

        func digits(_ count: Int) -> Int? {
            guard i + count <= s.count else { return nil }
            var value = 0
            for _ in 0..<count {
                let c = s[i]
                guard c >= 48, c <= 57 else { return nil }
                value = value * 10 + Int(c - 48)
                i += 1
            }
            return value
        }
        func expect(_ char: UInt8) -> Bool {
            guard i < s.count, s[i] == char else { return false }
            i += 1
            return true
        }

        guard let year = digits(4), expect(UInt8(ascii: "-")),
              let month = digits(2), expect(UInt8(ascii: "-")),
              let day = digits(2) else { return nil }
        guard i < s.count, s[i] == UInt8(ascii: "T") || s[i] == UInt8(ascii: " ") else { return nil }
        i += 1
        guard let hour = digits(2), expect(UInt8(ascii: ":")),
              let minute = digits(2), expect(UInt8(ascii: ":")),
              let second = digits(2) else { return nil }

        var fraction = 0.0
        if expect(UInt8(ascii: ".")) || expect(UInt8(ascii: ",")) {
            var scale = 0.1
            var any = false
            while i < s.count, s[i] >= 48, s[i] <= 57 {
                fraction += Double(s[i] - 48) * scale
                scale /= 10
                i += 1
                any = true
            }
            guard any else { return nil }
        }

        var offsetSeconds: Int? = 0
        if i == s.count {
            offsetSeconds = nil // no offset: PATH local time
        } else if expect(UInt8(ascii: "Z")) || expect(UInt8(ascii: "z")) {
            offsetSeconds = 0
        } else {
            let sign: Int
            if expect(UInt8(ascii: "+")) { sign = 1 } else if expect(UInt8(ascii: "-")) { sign = -1 } else { return nil }
            guard let oh = digits(2) else { return nil }
            var om = 0
            if i < s.count {
                _ = expect(UInt8(ascii: ":"))
                guard let m = digits(2) else { return nil }
                om = m
            }
            guard oh <= 18, om < 60 else { return nil }
            offsetSeconds = sign * (oh * 3600 + om * 60)
        }
        guard i == s.count else { return nil }
        guard (1...12).contains(month), (1...31).contains(day),
              hour < 24, minute < 60, second < 60 else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = offsetSeconds == nil ? pathTimeZone : TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let base = calendar.date(from: components),
              calendar.component(.day, from: base) == day else { return nil }
        return base.addingTimeInterval(fraction - TimeInterval(offsetSeconds ?? 0))
    }
}
