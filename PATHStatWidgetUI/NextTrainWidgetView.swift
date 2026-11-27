import PATHKit
import SwiftUI
import WidgetKit

/// The "Next PATH train" widget for one entry, shared by the widget extension and the app's
/// `-WidgetGallery` screenshot mode. `family` is explicit so the app can render every size.
///
/// Countdowns use `Text(timerInterval:countsDown:)` and clock times use `Text(_:style: .time)`,
/// so they stay correct between timeline entries without reloads.
struct NextTrainWidgetView: View {
    let state: WidgetEntryState
    let family: WidgetFamily
    var locationUnavailable = false
    /// True when rendered by the app (gallery) instead of WidgetKit. Outside WidgetKit a
    /// circular `ProgressView(timerInterval:)` draws as a spinner, so the gallery draws the
    /// ring as it looks at the entry date (full) instead.
    var rendersInApp = false

    var body: some View {
        switch family {
        case .systemMedium: MediumWidgetView(state: state, locationUnavailable: locationUnavailable)
        case .accessoryRectangular: RectangularWidgetView(state: state)
        case .accessoryInline: InlineWidgetView(state: state)
        case .accessoryCircular: CircularWidgetView(state: state, rendersInApp: rendersInApp)
        default: SmallWidgetView(state: state, locationUnavailable: locationUnavailable)
        }
    }
}

// MARK: - Shared pieces

extension WidgetEntryState {
    var next: TrainArrival? { trains.first }
    var following: TrainArrival? { trains.dropFirst().first }
    var destinationName: String { StationCatalog.station(trip.destination).shortName }
    /// "Grove St → 33rd St" (the trip's name, if any, is too long for small widgets).
    var shortTitle: String {
        "\(StationCatalog.station(trip.origin).shortName) → \(destinationName)"
    }
}

extension TrainArrival {
    var widgetHeadsign: String { headsign.isEmpty ? "PATH train" : headsign }

    /// "Train to 33rd Street, Journal Square–33rd St line, arrives 8:42 PM" (no countdown:
    /// a spoken countdown would be frozen at the entry date).
    var widgetAccessibilityLabel: String {
        "Train to \(widgetHeadsign), \(line?.displayName ?? "PATH") line, arrives \(arrival.formatted(date: .omitted, time: .shortened))"
    }
}

/// m:ss countdown to `train.arrival` that ticks on its own; "Due" once the entry's date is at
/// or past the arrival (the timeline has an entry at each arrival).
struct WidgetCountdown: View {
    let train: TrainArrival
    let date: Date

    var body: some View {
        if train.arrival <= date {
            Text("Due")
        } else {
            Text(timerInterval: date...train.arrival, countsDown: true)
                .monospacedDigit()
        }
    }
}

/// "Updated 3 min ago", orange when stale; "Can't update" when offline.
struct WidgetFooter: View {
    let state: WidgetEntryState

    var body: some View {
        Group {
            switch state.status {
            case .offline:
                Label("Can't update", systemImage: "wifi.slash")
                    .foregroundStyle(.orange)
            case .stale:
                updated.foregroundStyle(.orange)
            case .live:
                updated.foregroundStyle(.secondary)
            case .unavailable:
                Text("Tap to open").foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private var updated: some View {
        if let fetchedAt = state.fetchedAt {
            Text("Updated \(Text(fetchedAt, style: .relative)) ago")
        }
    }
}

struct WidgetLineDot: View {
    let train: TrainArrival
    var size: CGFloat = 8

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array((train.lineColors.isEmpty ? ["8E8E93"] : train.lineColors).enumerated()), id: \.offset) { _, hex in
                Circle().fill(Color(hex: hex)).frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// No trains / can't reach PATH, for system families.
struct WidgetEmptyState: View {
    let state: WidgetEntryState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch state.status {
            case .unavailable:
                Label("Can't reach PATH", systemImage: "wifi.exclamationmark")
                    .font(.subheadline.weight(.semibold))
            case .stale, .offline:
                Text("No upcoming trains")
                    .font(.subheadline.weight(.semibold))
                Text("Open for latest times")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .live:
                Text("No trains predicted")
                    .font(.subheadline.weight(.semibold))
                Text("Service may be suspended")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct WidgetTitle: View {
    let text: String
    let locationUnavailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if locationUnavailable {
                Label("Location unavailable", systemImage: "location.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - systemSmall

struct SmallWidgetView: View {
    let state: WidgetEntryState
    let locationUnavailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetTitle(text: state.shortTitle, locationUnavailable: locationUnavailable)
            Spacer(minLength: 0)
            if let next = state.next {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        WidgetLineDot(train: next)
                        Text(next.widgetHeadsign)
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    WidgetCountdown(train: next, date: state.date)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let following = state.following {
                        Text("then \(Text(following.arrival, style: .time))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rowsLabel)
            } else {
                WidgetEmptyState(state: state)
            }
            Spacer(minLength: 0)
            WidgetFooter(state: state)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var rowsLabel: String {
        state.trains.prefix(2).map(\.widgetAccessibilityLabel).joined(separator: "; ")
    }
}

// MARK: - systemMedium

struct MediumWidgetView: View {
    let state: WidgetEntryState
    let locationUnavailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetTitle(text: state.trip.title, locationUnavailable: locationUnavailable)
            if state.trains.isEmpty {
                Spacer(minLength: 0)
                WidgetEmptyState(state: state)
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 4) {
                    ForEach(state.trains.prefix(3)) { train in
                        row(train)
                    }
                }
                Spacer(minLength: 0)
            }
            WidgetFooter(state: state)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ train: TrainArrival) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(Array((train.lineColors.isEmpty ? ["8E8E93"] : train.lineColors).enumerated()), id: \.offset) { _, hex in
                    Capsule().fill(Color(hex: hex)).frame(width: 4)
                }
            }
            .frame(height: 22)
            Text(train.widgetHeadsign)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(train.arrival, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
            WidgetCountdown(train: train, date: state.date)
                .font(.subheadline.weight(.bold))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 64, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(train.widgetAccessibilityLabel)
    }
}

// MARK: - Lock Screen

struct RectangularWidgetView: View {
    let state: WidgetEntryState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(state.shortTitle)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let next = state.next {
                Text("\(countdownText(next)) \(next.widgetHeadsign)")
                    .font(.caption)
                    .lineLimit(1)
                if state.status == .stale || state.status == .offline {
                    statusLine
                } else if let following = state.following {
                    Text("then \(Text(following.arrival, style: .time))")
                        .font(.caption)
                        .lineLimit(1)
                } else {
                    statusLine
                }
            } else {
                Text(emptyText)
                    .font(.caption)
                statusLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var emptyText: String {
        switch state.status {
        case .unavailable: "Can't reach PATH"
        case .stale, .offline: "No upcoming trains"
        case .live: "No trains predicted"
        }
    }

    // One interpolated Text: a countdown/headsign HStack renders blank in WidgetKit's renderer.
    private func countdownText(_ next: TrainArrival) -> Text {
        if next.arrival <= state.date {
            Text("Due").font(.body.weight(.semibold))
        } else {
            Text(timerInterval: state.date...next.arrival, countsDown: true)
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch state.status {
        case .offline: Text("Can't update").font(.caption2)
        case .stale: Text("Out of date").font(.caption2)
        case .unavailable: Text("Tap to open").font(.caption2)
        case .live: EmptyView()
        }
    }

    private var accessibilityText: String {
        guard !state.trains.isEmpty else {
            let empty: String = switch state.status {
            case .unavailable: "can't reach PATH"
            case .stale, .offline: "no upcoming trains"
            case .live: "no trains predicted"
            }
            return "\(state.shortTitle), \(empty)"
        }
        return ([state.shortTitle] + state.trains.prefix(2).map(\.widgetAccessibilityLabel)).joined(separator: "; ")
    }
}

struct InlineWidgetView: View {
    let state: WidgetEntryState

    var body: some View {
        if let next = state.next {
            if next.arrival <= state.date {
                Text("\(state.destinationName) · Due")
            } else {
                Text("\(state.destinationName) · \(Text(timerInterval: state.date...next.arrival, countsDown: true))")
            }
        } else if state.status == .unavailable {
            Text("Can't reach PATH")
        } else if state.status == .stale || state.status == .offline {
            Text("\(state.destinationName) · Open for latest")
        } else {
            Text("\(state.destinationName) · No trains")
        }
    }
}

struct CircularWidgetView: View {
    let state: WidgetEntryState
    var rendersInApp = false

    var body: some View {
        if let next = state.next, next.arrival > state.date {
            Group {
                if rendersInApp {
                    ZStack {
                        Circle().stroke(.primary, lineWidth: 5).padding(3)
                        label(next)
                    }
                } else {
                    ProgressView(timerInterval: state.date...next.arrival, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        label(next)
                    }
                    .progressViewStyle(.circular)
                }
            }
            .accessibilityLabel(next.widgetAccessibilityLabel)
        } else {
            ZStack {
                Circle().strokeBorder(.secondary, lineWidth: 3)
                Text(state.next == nil ? "—" : "Due")
                    .font(.system(size: 14, weight: .semibold))
            }
            .accessibilityLabel(state.next == nil ? "No trains" : "Train due")
        }
    }

    private func label(_ next: TrainArrival) -> some View {
        Text(timerInterval: state.date...next.arrival, countsDown: true)
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 6)
    }
}
