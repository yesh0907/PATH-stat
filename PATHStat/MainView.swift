import CoreLocation
import PATHKit
import SwiftUI

/// The main screen: station, destination, and the next trains for the current trip.
struct MainView: View {
    let model: BoardModel
    let location: LocationService
    /// Live mode only: shares fetched snapshots with the widget.
    var widgetSync: WidgetSync?
    let liveActivities: LiveActivityController
    let feedback: FeedbackCenter

    /// Feed refresh cadence while the screen is visible and the app is active.
    static let refreshInterval: Duration = .seconds(20)

    @Environment(\.scenePhase) private var scenePhase
    @State private var showingStationPicker = false
    @State private var showingFeedbackSettings = false

    private struct RefreshKey: Hashable {
        let active: Bool
        let tripID: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if location.authorization == .denied {
                    LocationDeniedBanner(stationName: origin.shortName) { showingStationPicker = true }
                }
                stationHeader
                VStack(alignment: .leading, spacing: 10) {
                    tripHeader
                    DestinationChips(
                        options: model.destinationOptions,
                        selected: model.trip.destination,
                        select: model.selectDestination
                    )
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    BoardContent(model: model, now: context.date)
                }
                FavoritesSection(
                    favorites: model.favorites,
                    current: model.trip,
                    select: { model.select($0, manual: true) },
                    remove: model.removeFavorite,
                    startLiveActivity: startLiveActivity
                )
                LiveActivitySection(controller: liveActivities, trip: model.trip) {
                    startLiveActivity(model.trip)
                }
                FeedbackRow(center: feedback) { showingFeedbackSettings = true }
            }
            .padding()
        }
        .environment(feedback)
        .background(Color(.systemGroupedBackground))
        .refreshable { await model.refresh() }
        // Refresh now, then every 20 s; restarts when the trip changes or the app returns to
        // the foreground, and stops scheduling refreshes when inactive or hidden. A fetch
        // already in flight finishes so every caller gets its result.
        .task(id: RefreshKey(active: scenePhase == .active, tripID: model.trip.id)) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await model.refresh()
                do {
                    try await Task.sleep(for: Self.refreshInterval)
                } catch {
                    return
                }
            }
        }
        .task { location.start() }
        .task {
            feedback.contextProvider = { [model, location, liveActivities] context in
                FeedbackContextBuilder.fill(&context, model: model, location: location, liveActivities: liveActivities)
            }
            feedback.installDebugShakeButton()
            feedback.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                location.refresh()
                liveActivities.sync()
                feedback.sceneDidBecomeActive()
            }
            if phase == .background {
                widgetSync?.didEnterBackground()
                liveActivities.didEnterBackground()
            }
        }
        .onChange(of: model.lastFetchAt) { _, _ in
            // `lastFetchAt` only changes on a successful fetch.
            if let snapshot = model.snapshot { widgetSync?.didFetch(snapshot) }
            updateLiveActivity()
        }
        .onChange(of: model.errorMessage) { _, _ in updateLiveActivity() }
        .onChange(of: location.location, initial: true) { _, newLocation in
            model.locationDidChange(newLocation, authorization: location.authorization)
        }
        .onChange(of: location.authorization, initial: true) { _, authorization in
            model.locationDidChange(location.location, authorization: authorization)
        }
        .onOpenURL { url in
            if let trip = Trip(url: url) { model.select(trip, manual: true) }
        }
        .sheet(isPresented: $showingStationPicker) {
            StationPickerView(current: model.trip.origin, location: location.location, select: model.selectStation)
                .onAppear { feedback.currentScreen = "station picker" }
                .onDisappear { feedback.currentScreen = "main" }
        }
        .sheet(isPresented: $showingFeedbackSettings) {
            FeedbackSettingsView(center: feedback)
        }
    }

    private var origin: Station { StationCatalog.station(model.trip.origin) }

    private func startLiveActivity(_ trip: Trip) {
        Task { await liveActivities.start(trip: trip, snapshot: model.snapshot, fetchFailed: model.errorMessage != nil) }
    }

    private func updateLiveActivity() {
        Task { await liveActivities.update(snapshot: model.snapshot, fetchFailed: model.errorMessage != nil) }
    }

    // MARK: Header

    /// "nearest" / "home station" / "selected": the header's context, without any distance.
    static func stationContextWord(origin: StationCode, location: CLLocation?) -> String {
        if let location, StationCatalog.stations(nearest: location).first?.station.code == origin { return "nearest" }
        return origin == TripPlanner.homeStation ? "home station" : "selected"
    }

    private var stationContext: (text: String, spoken: String) {
        if let here = location.location,
           let nearest = StationCatalog.stations(nearest: here).first,
           nearest.station.code == origin.code {
            guard nearest.distance >= Format.nearbyThreshold else { return ("Nearest station", "nearest") }
            return (
                "Nearest station · \(Format.distance(nearest.distance))",
                "nearest, \(Format.distance(nearest.distance, wide: true))"
            )
        }
        if origin.code == TripPlanner.homeStation { return ("Home station", "home station") }
        return ("Selected station", "selected")
    }

    private var stationHeader: some View {
        let context = stationContext
        return Button { showingStationPicker = true } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(origin.name)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(context.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Station \(origin.name), \(context.spoken)")
        .accessibilityHint("Double tap to change.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("station-header")
    }

    private var tripHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.trip.title)
                .font(.headline)
                .accessibilityIdentifier("trip-title")
            Spacer(minLength: 8)
            Button(action: model.toggleFavorite) {
                Image(systemName: model.isCurrentTripFavorite ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(model.isCurrentTripFavorite ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isCurrentTripFavorite ? "Remove from Favorites" : "Add to Favorites")
            .accessibilityIdentifier("favorite-toggle")
        }
    }
}

// MARK: - Board

/// Loading / offline / no trains / trains, plus the offline banner and freshness footer.
private struct BoardContent: View {
    let model: BoardModel
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let board = model.board(now: now) {
                if model.errorMessage != nil, let fetchedAt = model.lastFetchAt {
                    OfflineBanner(age: now.timeIntervalSince(fetchedAt))
                }
                if board.trains.isEmpty {
                    NoTrainsState(destination: StationCatalog.station(model.trip.destination))
                } else {
                    trains(board)
                }
                FreshnessFooter(board: board, now: now)
            } else if let error = model.errorMessage {
                OfflineState(message: error, isRetrying: model.isLoading) {
                    Task { await model.refresh() }
                }
            } else {
                ProgressView("Loading trains…")
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .accessibilityIdentifier("state-loading")
            }
        }
    }

    @ViewBuilder
    private func trains(_ board: DepartureBoard) -> some View {
        if let next = board.next {
            TrainCard(train: next, now: now, prominence: .next)
        }
        if let following = board.following {
            TrainCard(train: following, now: now, prominence: .following)
        }
        let later = Array(board.trains.dropFirst(2).prefix(2))
        if !later.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Later")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                ForEach(Array(later.enumerated()), id: \.element.id) { index, train in
                    if index > 0 { Divider() }
                    LaterTrainRow(train: train, now: now, index: index)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct NoTrainsState: View {
    let destination: Station

    @Environment(FeedbackCenter.self) private var feedback: FeedbackCenter?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tram")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No trains to \(destination.shortName) right now")
                .font(.headline)
            Text("Service may be suspended, or it may be late at night. Pull down to refresh.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("state-no-trains")
        .onAppear { feedback?.record("No trains to \(destination.shortName)") }
    }
}

private struct OfflineState: View {
    let message: String
    let isRetrying: Bool
    let retry: () -> Void

    @Environment(FeedbackCenter.self) private var feedback: FeedbackCenter?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Can't reach PATH")
                .font(.headline)
                .accessibilityIdentifier("state-offline")
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(action: retry) {
                if isRetrying {
                    ProgressView()
                } else {
                    Text("Retry")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRetrying)
            .accessibilityLabel("Retry")
            .accessibilityIdentifier("retry-button")
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { feedback?.record("Can't reach PATH: \(message)") }
    }
}

private struct OfflineBanner: View {
    let age: TimeInterval

    @Environment(FeedbackCenter.self) private var feedback: FeedbackCenter?

    var body: some View {
        Label("Can't update — showing data from \(Format.age(age)) ago", systemImage: "wifi.slash")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("offline-banner")
            .onAppear { feedback?.record("Can't update — showing old data") }
    }
}

private struct FreshnessFooter: View {
    let board: DepartureBoard
    let now: Date

    @Environment(FeedbackCenter.self) private var feedback: FeedbackCenter?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let age = board.age(at: now) {
                Text("Updated \(Format.age(age)) ago")
            } else {
                Text("No update time from PATH")
            }
            if case .stale = board.freshness(at: now) {
                Label("PATH data may be out of date", systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
                    .onAppear { feedback?.record("PATH data may be out of date") }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("freshness-footer")
    }
}

// MARK: - Destination chips

private struct DestinationChips: View {
    let options: (termini: [DestinationOption], otherStops: [DestinationOption])
    let selected: StationCode
    let select: (StationCode) -> Void

    /// Termini, plus the selected destination when it's an intermediate stop.
    private var chips: [DestinationOption] {
        options.termini + options.otherStops.filter { $0.destination == selected }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                chipRow
            }
            .scrollClipDisabled()
            // Keep the selected chip visible (e.g. "to Grove St" after the termini).
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: chips) { _, _ in
                withAnimation { proxy.scrollTo(selected, anchor: .center) }
            }
            .onChange(of: selected) { _, selected in
                withAnimation { proxy.scrollTo(selected, anchor: .center) }
            }
        }
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            ForEach(chips) { option in
                chip(option).id(option.destination)
            }
            if !options.otherStops.isEmpty {
                Menu {
                    ForEach(options.otherStops) { option in
                        Button { select(option.destination) } label: {
                            if option.destination == selected {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
                .accessibilityLabel("More destinations")
                .accessibilityIdentifier("more-destinations")
            }
        }
    }

    private func chip(_ option: DestinationOption) -> some View {
        let isSelected = option.destination == selected
        return Button { select(option.destination) } label: {
            Text(option.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Destination \(StationCatalog.station(option.destination).shortName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("destination-\(option.destination.rawValue)")
    }
}

// MARK: - Banners and placeholders

private struct LocationDeniedBanner: View {
    let stationName: String
    let chooseStation: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(FeedbackCenter.self) private var feedback: FeedbackCenter?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Location is off — showing \(stationName)", systemImage: "location.slash.fill")
                .font(.subheadline.weight(.semibold))
            ViewThatFits(in: .horizontal) {
                HStack { buttons }
                VStack(alignment: .leading) { buttons }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("location-denied-banner")
        .onAppear { feedback?.record("Location is off") }
    }

    @ViewBuilder
    private var buttons: some View {
        Button("Choose station", action: chooseStation)
            .buttonStyle(.bordered)
            .accessibilityIdentifier("choose-station-button")
        Button("Open Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("open-settings-button")
    }
}

/// Start / stop the Live Activity for the current trip, or switch it from another trip.
private struct LiveActivitySection: View {
    let controller: LiveActivityController
    let trip: Trip
    let start: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(FeedbackCenter.self) private var feedback: FeedbackCenter?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let active = controller.activeTrip {
                status(active)
                if !active.sameRoute(as: trip) {
                    startButton("Switch to this trip", hint: "Shows \(trip.title) on the Lock Screen instead.")
                }
                Button(role: .destructive) {
                    Task { await controller.stop() }
                } label: {
                    Label("Stop Live Activity", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("live-activity-stop")
            } else if controller.areActivitiesEnabled {
                startButton("Start Live Activity", hint: "Shows the next trains on the Lock Screen and in the Dynamic Island.")
            } else {
                Text("Live Activities are turned off for PATH Stat. Turn them on in Settings to see the next trains on your Lock Screen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("live-activity-disabled")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("live-activity-settings")
            }
            if let error = controller.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("live-activity-error")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: controller.errorMessage, initial: true) { _, error in
            if let error { feedback?.record("Live Activity: \(error)") }
        }
    }

    private func startButton(_ title: String, hint: String) -> some View {
        Button(action: start) {
            Label(title, systemImage: "dot.radiowaves.left.and.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint(hint)
        .accessibilityIdentifier("live-activity-button")
    }

    @ViewBuilder
    private func status(_ active: Trip) -> some View {
        let isThisTrip = active.sameRoute(as: trip)
        Group {
            if let endsAt = controller.endsAt {
                if isThisTrip {
                    Text("Live on Lock Screen · until \(Text(endsAt, style: .time))")
                } else {
                    Text("Live on Lock Screen: \(active.title) · until \(Text(endsAt, style: .time))")
                }
            } else {
                Text(isThisTrip ? "Live on Lock Screen" : "Live on Lock Screen: \(active.title)")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.green)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("live-activity-status")
    }
}

// MARK: - Feedback

/// Send feedback, feedback settings, and how many reports are waiting to send.
private struct FeedbackRow: View {
    let center: FeedbackCenter
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { center.present(trigger: .button) } label: {
                    Label("Send feedback", systemImage: "exclamationmark.bubble")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Shake the phone to report from any screen.")
                .accessibilityIdentifier("send-feedback-button")
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Feedback settings")
                .accessibilityIdentifier("feedback-settings-button")
            }
            if center.pendingCount > 0 {
                Button(action: openSettings) {
                    Label(
                        center.pendingCount == 1 ? "1 report waiting to send" : "\(center.pendingCount) reports waiting to send",
                        systemImage: "tray.and.arrow.up"
                    )
                    .font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("feedback-pending")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Fills a report's context from the main screen's state. Location is reduced to the
/// permission and the station header's context word; never coordinates or distances.
@MainActor
enum FeedbackContextBuilder {
    static func fill(_ context: inout FeedbackContext, model: BoardModel, location: LocationService, liveActivities: LiveActivityController) {
        let now = Date.now
        context.trip = FeedbackContext.tripDescription(model.trip)
        context.stationContext = MainView.stationContextWord(origin: model.trip.origin, location: location.location)
        context.locationPermission = switch location.authorization {
        case .authorized: "authorized"
        case .denied: "denied"
        case .notDetermined: "not determined"
        }
        context.feedFetchedAt = model.lastFetchAt
        context.lastFeedError = model.errorMessage
        if let board = model.board(now: now) {
            context.feedAgeSeconds = board.age(at: now).map { Int($0) }
            context.feedFreshness = switch board.freshness(at: now) {
            case .fresh: "fresh"
            case .stale: "stale"
            case .unknown: "unknown"
            }
        }
        var live: String
        if let trip = liveActivities.activeTrip {
            live = "Live: \(trip.title)"
            if let endsAt = liveActivities.endsAt {
                live += " until \(endsAt.formatted(Date.ISO8601FormatStyle()))"
            }
        } else {
            live = liveActivities.areActivitiesEnabled ? "Off" : "Disabled in Settings"
        }
        if let error = liveActivities.errorMessage { live += " (error: \(error))" }
        context.liveActivity = live
    }
}

// MARK: - Previews

#Preview("Trains") {
    let environment = Scenario.trains.makeEnvironment()
    MainView(model: environment.model, location: environment.location, liveActivities: environment.liveActivities, feedback: environment.feedback)
}

#Preview("Near 23rd St") {
    let environment = Scenario.trains.makeEnvironment(location: StationCatalog.station(.twentyThirdStreet).location)
    MainView(model: environment.model, location: environment.location, liveActivities: environment.liveActivities, feedback: environment.feedback)
}

#Preview("Loading") {
    let environment = Scenario.loading.makeEnvironment()
    MainView(model: environment.model, location: environment.location, liveActivities: environment.liveActivities, feedback: environment.feedback)
}

#Preview("No trains") {
    let environment = Scenario.noTrains.makeEnvironment()
    MainView(model: environment.model, location: environment.location, liveActivities: environment.liveActivities, feedback: environment.feedback)
}

#Preview("Offline") {
    let environment = Scenario.offline.makeEnvironment()
    MainView(model: environment.model, location: environment.location, liveActivities: environment.liveActivities, feedback: environment.feedback)
}

#Preview("Offline with data") {
    let environment = Scenario.offlineWithData.makeEnvironment()
    MainView(model: environment.model, location: environment.location, liveActivities: environment.liveActivities, feedback: environment.feedback)
}

#Preview("Location denied") {
    let environment = Scenario.locationDenied.makeEnvironment()
    MainView(model: environment.model, location: environment.location, liveActivities: environment.liveActivities, feedback: environment.feedback)
}
