import PATHKit
import SwiftUI

/// `-LiveActivityGallery <live|rolledOver|stale|offline|ended>`: the shared Live Activity views
/// for one fixed sample state, on mock Lock Screen and Dynamic Island chrome, for screenshots.
/// Never touches ActivityKit or the caches (the Refresh button is drawn non-interactive).
struct LiveActivityGalleryView: View {
    let state: TrainActivitySampleState
    /// Fixed at launch so the sample is built once.
    @State private var now = Date.now

    var body: some View {
        let sample = state.make(now: now)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Live Activity gallery · \(state.rawValue)")
                    .font(.headline)
                    .foregroundStyle(.white)

                section("Lock Screen") {
                    TrainActivityLockScreenView(trip: sample.trip, state: sample.state, isStale: sample.isStale, interactive: false)
                        .background(TrainActivityStyle.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("live-activity-lockscreen")
                }

                section("Dynamic Island · compact") {
                    HStack(spacing: 0) {
                        TrainActivityCompactLeadingView(trip: sample.trip, state: sample.state, isStale: sample.isStale)
                        Spacer(minLength: 90)
                        TrainActivityCompactTrailingView(trip: sample.trip, state: sample.state, isStale: sample.isStale)
                    }
                    .padding(.horizontal, 14)
                    .frame(width: 250, height: 37)
                    .background(Color.black, in: Capsule())
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("live-activity-compact")
                }

                section("Dynamic Island · minimal") {
                    TrainActivityMinimalView(trip: sample.trip, state: sample.state, isStale: sample.isStale)
                        .frame(width: 37, height: 37)
                        .background(Color.black, in: Circle())
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("live-activity-minimal")
                }

                section("Dynamic Island · expanded") {
                    VStack(spacing: 10) {
                        HStack(alignment: .top) {
                            TrainActivityExpandedLeadingView(trip: sample.trip, state: sample.state, isStale: sample.isStale)
                            Spacer(minLength: 8)
                            TrainActivityExpandedTrailingView(trip: sample.trip, state: sample.state, isStale: sample.isStale)
                        }
                        TrainActivityExpandedBottomView(trip: sample.trip, state: sample.state, isStale: sample.isStale, interactive: false)
                    }
                    .padding(18)
                    .frame(width: 370)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 44, style: .continuous))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("live-activity-expanded")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Wallpaper-like backdrop: Live Activities sit over the Lock Screen wallpaper.
        .background(
            LinearGradient(
                colors: [Color(red: 0.18, green: 0.22, blue: 0.38), Color(red: 0.42, green: 0.27, blue: 0.40)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .environment(\.colorScheme, .dark)
        .accessibilityIdentifier("live-activity-gallery")
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.75))
            content()
        }
    }
}

#Preview("Live") { LiveActivityGalleryView(state: .live) }
#Preview("Rolled over") { LiveActivityGalleryView(state: .rolledOver) }
#Preview("Stale") { LiveActivityGalleryView(state: .stale) }
#Preview("Offline") { LiveActivityGalleryView(state: .offline) }
#Preview("Ended") { LiveActivityGalleryView(state: .ended) }
