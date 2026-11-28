import PATHKit
import SwiftUI

extension TrainArrival {
    /// A plausible train for placeholders and the fixed-height board skeleton.
    static func dummy(now: Date) -> TrainArrival {
        TrainArrival(
            station: .groveStreet, direction: .toNY, target: .thirtyThirdStreet, headsign: "33rd Street",
            line: .journalSquare33rd, lineColors: ["FF9900"], arrival: now.addingTimeInterval(300),
            arrivalTimeMessage: "", lastUpdated: now
        )
    }
}

enum TrainCardProminence {
    case next
    case following

    var title: String { self == .next ? "Next train" : "Following train" }
    var identifier: String { self == .next ? "next-train" : "following-train" }
}

/// The train information rows of a card: color bars, headsign, line, countdown.
/// No padding, background or accessibility container — the caller supplies those.
struct TrainInfo: View {
    let train: TrainArrival
    let now: Date
    let prominence: TrainCardProminence

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
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .minimumScaleFactor(0.8)
                    lineText
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
    }

    /// The line name, with "Delayed" appended in orange so a delayed train adds no row.
    private var lineText: Text {
        if train.isDelayed {
            Text("\(Text(train.lineName)) · \(Text("Delayed").foregroundStyle(.orange))")
        } else {
            Text(train.lineName)
        }
    }

    private var countdownFont: Font {
        switch prominence {
        case .next: .system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit()
        case .following: .system(.title2, design: .rounded).weight(.semibold).monospacedDigit()
        }
    }
}

/// The following (smaller) train card, and the placeholder/skeleton card layout.
struct TrainCard: View {
    typealias Prominence = TrainCardProminence

    let train: TrainArrival
    let now: Date
    let prominence: Prominence

    var body: some View {
        TrainInfo(train: train, now: now, prominence: prominence)
            .padding(prominence == .next ? 16 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(train.spokenDescription(prefix: prominence.title, at: now))
            .accessibilityIdentifier(prominence.identifier)
    }
}

/// A compact row for trains after the following one (minutes only).
struct LaterTrainRow: View {
    let train: TrainArrival
    let now: Date
    let index: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            LineColorBars(colors: train.lineColors)
            VStack(alignment: .leading, spacing: 0) {
                Text(train.headsign.isEmpty ? "PATH train" : train.headsign)
                    .font(.body)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .minimumScaleFactor(0.8)
                Text(train.lineName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        let destination = train.headsign.isEmpty ? "unknown destination" : train.headsign
        var label = "Later train to \(destination), \(train.lineName) line, \(when)"
        if train.isDelayed { label += ", delayed" }
        return label
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
