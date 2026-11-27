import AppIntents
import PATHKit
import SwiftUI

// Live Activity views, shared by the widget extension (`TrainLiveActivity`) and the app's
// `-LiveActivityGallery` mode. Every view takes the trip, state and `isStale` explicitly.
//
// Countdowns are only `Text(timerInterval:countsDown:)` and clock times only
// `Text(_:style: .time/.relative)`, so they tick without updates. When the content goes stale
// (at `state.staleAt`, at the latest the first train's departure) the system re-renders with
// `isStale == true` and `visibleTrains(isStale:)` rolls over to the following train.

/// What every Live Activity view needs, derived once.
struct TrainActivityDisplay {
    let trip: Trip
    let state: TrainActivityState
    let isStale: Bool

    var trains: [TrainArrival] { state.status == .ended ? [] : state.visibleTrains(isStale: isStale) }
    var next: TrainArrival? { trains.first }
    var following: TrainArrival? { trains.dropFirst().first }
    var warning: Bool { state.showsStaleWarning(isStale: isStale) }
    var destinationName: String { StationCatalog.station(trip.destination).shortName }
}

enum TrainActivityStyle {
    /// Lock Screen background: dark in both appearances, so white text keeps its contrast.
    static let background = Color(red: 0.08, green: 0.09, blue: 0.11).opacity(0.92)
    static let secondary = Color.white.opacity(0.7)
    static let warning = Color.orange
}

/// m:ss countdown to `train.arrival`, ticking on its own (0:00 once it has arrived).
struct TrainActivityCountdown: View {
    let train: TrainArrival

    var body: some View {
        Text(timerInterval: Date.now...max(train.arrival, .now), countsDown: true)
            .monospacedDigit()
    }
}

/// "Updated 2 min ago" (orange with an exclamation mark when the data may be out of date),
/// "Can't update · showing data from 5 min ago" when offline.
struct TrainActivityFreshness: View {
    let display: TrainActivityDisplay

    var body: some View {
        Group {
            if let fetchedAt = display.state.fetchedAt {
                if display.state.status == .offline {
                    Label {
                        Text("Can't update · showing data from \(Text(fetchedAt, style: .relative)) ago")
                    } icon: {
                        Image(systemName: "wifi.slash")
                    }
                    .foregroundStyle(TrainActivityStyle.warning)
                } else if display.warning {
                    Label {
                        Text("Updated \(Text(fetchedAt, style: .relative)) ago")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(TrainActivityStyle.warning)
                } else {
                    Text("Updated \(Text(fetchedAt, style: .relative)) ago")
                        .foregroundStyle(TrainActivityStyle.secondary)
                }
            } else {
                Label("Can't reach PATH", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(TrainActivityStyle.warning)
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

/// The Refresh button (`RefreshTrainActivityIntent`, performed in the app's process). The
/// app's gallery passes `interactive: false` so a tap never touches ActivityKit or the network.
struct TrainActivityRefreshButton: View {
    var interactive = true

    var body: some View {
        if interactive {
            Button(intent: RefreshTrainActivityIntent()) { label }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh")
        } else {
            label.accessibilityLabel("Refresh")
        }
    }

    private var label: some View {
        Image(systemName: "arrow.clockwise")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(6)
            .background(Color.white.opacity(0.18), in: Circle())
    }
}

/// "Then 33rd Street · 8:52" (a live countdown).
struct TrainActivityFollowing: View {
    let train: TrainArrival

    var body: some View {
        HStack(spacing: 4) {
            Text("Then \(train.widgetHeadsign)")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            TrainActivityCountdown(train: train)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(TrainActivityStyle.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Then: \(train.widgetAccessibilityLabel)")
    }
}

/// No trains / ended, for the Lock Screen and the expanded Dynamic Island.
struct TrainActivityEmpty: View {
    let display: TrainActivityDisplay

    var body: some View {
        Group {
            if display.state.status == .ended {
                Label("Live Activity ended · open PATH Stat to restart", systemImage: "flag.checkered")
            } else {
                Label("No trains predicted", systemImage: "tram")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
    }
}

// MARK: - Lock Screen / banner

struct TrainActivityLockScreenView: View {
    let trip: Trip
    let state: TrainActivityState
    let isStale: Bool
    var interactive = true

    private var display: TrainActivityDisplay { TrainActivityDisplay(trip: trip, state: state, isStale: isStale) }

    var body: some View {
        let display = display
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(trip.title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if state.status != .ended {
                    Text("Until \(Text(state.endsAt, style: .time))")
                        .font(.caption2)
                        .foregroundStyle(TrainActivityStyle.secondary)
                }
            }
            if let next = display.next {
                HStack(alignment: .center, spacing: 10) {
                    LineColorBars(colors: next.lineColors, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.widgetHeadsign)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("Arrives \(Text(next.arrival, style: .time))")
                            .font(.caption)
                            .foregroundStyle(TrainActivityStyle.secondary)
                    }
                    Spacer(minLength: 8)
                    TrainActivityCountdown(train: next)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: 120, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Next: \(next.widgetAccessibilityLabel)")
                if let following = display.following {
                    TrainActivityFollowing(train: following)
                }
            } else {
                TrainActivityEmpty(display: display)
            }
            HStack(spacing: 8) {
                TrainActivityFreshness(display: display)
                Spacer(minLength: 4)
                if state.status != .ended {
                    TrainActivityRefreshButton(interactive: interactive)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Dynamic Island

/// Compact leading: line colour + destination short name.
struct TrainActivityCompactLeadingView: View {
    let trip: Trip
    let state: TrainActivityState
    let isStale: Bool

    var body: some View {
        let display = TrainActivityDisplay(trip: trip, state: state, isStale: isStale)
        HStack(spacing: 4) {
            if let next = display.next {
                LineColorBars(colors: next.lineColors, height: 14)
            } else {
                Image(systemName: "tram.fill").foregroundStyle(TrainActivityStyle.secondary)
            }
            Text(display.destinationName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(display.warning ? TrainActivityStyle.warning : .white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("To \(display.destinationName)")
    }
}

/// Compact trailing: the next train's countdown, width-constrained (timer text is greedy).
struct TrainActivityCompactTrailingView: View {
    let trip: Trip
    let state: TrainActivityState
    let isStale: Bool

    var body: some View {
        let display = TrainActivityDisplay(trip: trip, state: state, isStale: isStale)
        Group {
            if let next = display.next {
                TrainActivityCountdown(train: next)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 46, alignment: .trailing)
                    .accessibilityLabel(next.widgetAccessibilityLabel)
            } else {
                Text("—").accessibilityLabel(state.status == .ended ? "Ended" : "No trains")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(display.warning ? TrainActivityStyle.warning : .white)
    }
}

/// Minimal: countdown, or a tram when there is no train to count down to.
struct TrainActivityMinimalView: View {
    let trip: Trip
    let state: TrainActivityState
    let isStale: Bool

    var body: some View {
        let display = TrainActivityDisplay(trip: trip, state: state, isStale: isStale)
        Group {
            if let next = display.next {
                TrainActivityCountdown(train: next)
                    .font(.system(size: 11, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: 36)
                    .accessibilityLabel(next.widgetAccessibilityLabel)
            } else {
                Image(systemName: "tram.fill")
                    .accessibilityLabel(state.status == .ended ? "PATH Live Activity ended" : "No PATH trains")
            }
        }
        .foregroundStyle(display.warning ? TrainActivityStyle.warning : .white)
    }
}

/// Expanded leading: line colour bars and the next train's headsign.
struct TrainActivityExpandedLeadingView: View {
    let trip: Trip
    let state: TrainActivityState
    let isStale: Bool

    var body: some View {
        let display = TrainActivityDisplay(trip: trip, state: state, isStale: isStale)
        HStack(spacing: 8) {
            if let next = display.next {
                LineColorBars(colors: next.lineColors, height: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(next.widgetHeadsign)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    Text("Arrives \(Text(next.arrival, style: .time))")
                        .font(.caption2)
                        .foregroundStyle(TrainActivityStyle.secondary)
                }
            } else {
                Text(trip.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
        }
        .foregroundStyle(.white)
        .padding(.leading, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Expanded trailing: the big countdown.
struct TrainActivityExpandedTrailingView: View {
    let trip: Trip
    let state: TrainActivityState
    let isStale: Bool

    var body: some View {
        let display = TrainActivityDisplay(trip: trip, state: state, isStale: isStale)
        Group {
            if let next = display.next {
                TrainActivityCountdown(train: next)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: 110, alignment: .trailing)
                    .accessibilityLabel(next.widgetAccessibilityLabel)
            } else {
                Image(systemName: "tram.fill")
                    .font(.title2)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(.white)
        .padding(.trailing, 4)
    }
}

/// Expanded bottom: the following train, freshness and Refresh (or the empty/ended message).
struct TrainActivityExpandedBottomView: View {
    let trip: Trip
    let state: TrainActivityState
    let isStale: Bool
    var interactive = true

    var body: some View {
        let display = TrainActivityDisplay(trip: trip, state: state, isStale: isStale)
        VStack(alignment: .leading, spacing: 6) {
            if display.next == nil {
                TrainActivityEmpty(display: display)
            } else if let following = display.following {
                TrainActivityFollowing(train: following)
            }
            HStack(spacing: 8) {
                TrainActivityFreshness(display: display)
                Spacer(minLength: 4)
                if state.status != .ended {
                    TrainActivityRefreshButton(interactive: interactive)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .environment(\.colorScheme, .dark)
    }
}
