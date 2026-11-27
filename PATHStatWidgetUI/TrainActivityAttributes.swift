import ActivityKit
import PATHKit

/// The "Next PATH train" Live Activity: a fixed trip, with `TrainActivityState` as its content.
struct TrainActivityAttributes: ActivityAttributes {
    typealias ContentState = TrainActivityState

    let trip: Trip
}
