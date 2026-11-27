import PATHKit
import SwiftUI

extension Color {
    /// A colour from a 6-digit hex string such as the feed's `lineColor` ("FF9900").
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        let value = UInt64(cleaned.prefix(6), radix: 16) ?? 0x888888
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension PATHLine {
    /// Individual hex colours (the via-Hoboken service has two).
    var colorHexes: [String] { colorHex.split(separator: ",").map(String.init) }
}

/// Vertical line-colour bars for a train; one bar per colour. With no `height`, the bars
/// stretch to the height of their container.
struct LineColorBars: View {
    let colors: [String]
    var height: CGFloat?

    @ScaledMetric(relativeTo: .body) private var barWidth: CGFloat = 6

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array((colors.isEmpty ? ["8E8E93"] : colors).enumerated()), id: \.offset) { _, hex in
                Capsule().fill(Color(hex: hex))
                    .frame(width: barWidth, height: height)
                    .frame(maxHeight: height == nil ? .infinity : nil)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Small line-colour dots, e.g. in the station picker.
struct LineDots: View {
    let lines: [PATHLine]

    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 8

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(lines.flatMap(\.colorHexes).reduce(into: [String]()) { seen, hex in
                if !seen.contains(hex) { seen.append(hex) }
            }.enumerated()), id: \.offset) { _, hex in
                Circle().fill(Color(hex: hex)).frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}
