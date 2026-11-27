import ActivityKit
import PATHKit
import SwiftUI
import WidgetKit

/// The "Next PATH train" Live Activity: Lock Screen / banner and Dynamic Island, using the
/// shared views in `PATHStatWidgetUI/TrainActivityViews.swift`. Started and updated by the app
/// (`TrainActivities`); between updates it re-renders at `staleDate` with `isStale`.
struct TrainLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrainActivityAttributes.self) { context in
            TrainActivityLockScreenView(trip: context.attributes.trip, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(TrainActivityStyle.background)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(context.attributes.trip.url)
        } dynamicIsland: { context in
            let trip = context.attributes.trip
            let state = context.state
            let isStale = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TrainActivityExpandedLeadingView(trip: trip, state: state, isStale: isStale)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TrainActivityExpandedTrailingView(trip: trip, state: state, isStale: isStale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TrainActivityExpandedBottomView(trip: trip, state: state, isStale: isStale)
                }
            } compactLeading: {
                TrainActivityCompactLeadingView(trip: trip, state: state, isStale: isStale)
            } compactTrailing: {
                TrainActivityCompactTrailingView(trip: trip, state: state, isStale: isStale)
            } minimal: {
                TrainActivityMinimalView(trip: trip, state: state, isStale: isStale)
            }
            .widgetURL(trip.url)
            .keylineTint(Color(hex: state.trains.first?.lineColors.first ?? "8E8E93"))
        }
    }
}

// MARK: - Previews

private let previewAttributes = TrainActivityAttributes(trip: .groveTo33rd)

private func previewStates() -> [TrainActivityState] {
    let now = Date.now
    return TrainActivitySampleState.allCases.map { $0.make(now: now).state }
}

#Preview("Lock Screen", as: .content, using: previewAttributes) {
    TrainLiveActivity()
} contentStates: {
    for state in previewStates() { state }
}

#Preview("Compact", as: .dynamicIsland(.compact), using: previewAttributes) {
    TrainLiveActivity()
} contentStates: {
    for state in previewStates() { state }
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: previewAttributes) {
    TrainLiveActivity()
} contentStates: {
    for state in previewStates() { state }
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: previewAttributes) {
    TrainLiveActivity()
} contentStates: {
    for state in previewStates() { state }
}
