import PATHKit
import SwiftUI

/// The next (big) or following (smaller) train for the current trip.
struct TrainCard: View {
    enum Prominence {
        case next
        case following

        var title: String { self == .next ? "Next train" : "Following train" }
        var identifier: String { self == .next ? "next-train" : "following-train" }
    }

    let train: TrainArrival
    let now: Date
    let prominence: Prominence

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        HStack(spacing: 12) {
            LineColorBars(colors: train.lineColors)
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(prominence.title)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(train.headsign.isEmpty ? "PATH train" : train.headsign)
                        .font(prominence == .next ? .title2.bold() : .headline)
                    Text(train.lineName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if train.isDelayed {
                        Label("Delayed", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                if !stacked { Spacer(minLength: 8) }
                VStack(alignment: stacked ? .leading : .trailing, spacing: 2) {
                    Text(Format.countdown(train.secondsRemaining(at: now)))
                        .font(countdownFont)
                        .contentTransition(.numericText(countsDown: true))
                    Text("at \(Format.clock(train.arrival))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(prominence == .next ? 16 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(train.spokenDescription(prefix: prominence.title, at: now))
        .accessibilityIdentifier(prominence.identifier)
    }

    private var countdownFont: Font {
        switch prominence {
        case .next: .system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit()
        case .following: .system(.title2, design: .rounded).weight(.semibold).monospacedDigit()
        }
    }
}

/// A compact row for trains after the following one (minutes only).
struct LaterTrainRow: View {
    let train: TrainArrival
    let now: Date
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            LineColorBars(colors: train.lineColors)
            VStack(alignment: .leading, spacing: 0) {
                Text(train.headsign.isEmpty ? "PATH train" : train.headsign).font(.body)
                Text(train.lineName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(Format.minutes(train, at: now))
                .font(.body.monospacedDigit().weight(.semibold))
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(laterLabel)
        .accessibilityIdentifier("later-train-\(index)")
    }

    private var laterLabel: String {
        let minutes = train.minutesRemaining(at: now)
        let when = minutes == 0 ? "arriving now" : "in \(minutes) minute\(minutes == 1 ? "" : "s")"
        return "Later train to \(train.headsign), \(train.lineName) line, \(when)"
    }
}

extension TrainArrival {
    var lineName: String { line?.displayName ?? "PATH" }

    var isDelayed: Bool {
        arrivalTimeMessage.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Delayed") == .orderedSame
    }

    /// "Next train to 33rd Street, Journal Square–33rd St line, arriving in 4 minutes, 12 seconds, at 8:42 PM".
    func spokenDescription(prefix: String, at now: Date) -> String {
        var parts = [
            "\(prefix) to \(headsign.isEmpty ? "unknown destination" : headsign)",
            "\(lineName) line",
            "arriving \(Format.spokenCountdown(secondsRemaining(at: now)))",
            "at \(Format.clock(arrival))",
        ]
        if isDelayed { parts.append("delayed") }
        return parts.joined(separator: ", ")
    }
}
