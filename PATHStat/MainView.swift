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
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        stationHeader
                        Button { feedback.present(trigger: .button) } label: {
                            Image(systemName: "exclamationmark.bubble")
                                .font(.title3)
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Send feedback")
                        .accessibilityHint("Report a bug, design nit, frustration, or idea.")
                        .accessibilityIdentifier("send-feedback-button")
                    }
                    if feedback.pendingCount > 0 {
                        Button { showingFeedbackSettings = true } label: {
                            Label(
                                feedback.pendingCount == 1 ? "1 report waiting to send" : "\(feedback.pendingCount) reports waiting to send",
                                systemImage: "tray.and.arrow.up"
                            )
                            .font(.footnote)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("feedback-pending")
                    }
                }
                DirectionControl(
                    quick: model.quickDestinations,
                    options: model.destinationOptions,
                    selected: model.trip.destination,
                    select: model.selectDestination
                )
                tripHeader
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    BoardContent(model: model, now: context.date, liveActivities: liveActivities) {
                        startLiveActivity(model.trip)
                    }
                }
                FavoritesSection(
                    favorites: model.favorites,
                    current: model.trip,
                    select: { model.select($0, manual: true) },
                    remove: model.removeFavorite,
                    startLiveActivity: startLiveActivity
                )
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

// MARK: - Direction control

/// Three equal-width segments in one capsule track — the two quick destinations, then a menu
/// of everything else. The accent pill slides between segments with no layout shift: same
/// width, font weight and padding whether selected or not.
private struct DirectionControl: View {
    let quick: [StationCode]
    let options: (termini: [DestinationOption], otherStops: [DestinationOption])
    let selected: StationCode
    let select: (StationCode) -> Void

    @Namespace private var namespace

    /// The menu segment shows the destination when it isn't one of the quick picks.
    private var moreIsSelected: Bool { !quick.contains(selected) }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(quick, id: \.self) { code in
                quickSegment(code)
            }
            moreSegment
        }
        .padding(4)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .animation(.snappy, value: selected)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("direction-control")
    }

    @ViewBuilder
    private func quickSegment(_ code: StationCode) -> some View {
        let isSelected = selected == code
        Button { select(code) } label: {
            Group {
                if code == TripPlanner.homeStation {
                    Label("Home", systemImage: "house.fill")
                } else {
                    Text(StationCatalog.station(code).shortName)
                }
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor)
                        .matchedGeometryEffect(id: "selected-pill", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(code == TripPlanner.homeStation
            ? "Destination \(StationCatalog.station(code).shortName), home"
            : "Destination \(StationCatalog.station(code).shortName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("destination-\(code.rawValue)")
    }

    private var moreSegment: some View {
        Menu {
            ForEach(options.termini) { option in
                menuButton(option)
            }
            if !options.termini.isEmpty, !options.otherStops.isEmpty {
                Divider()
            }
            ForEach(options.otherStops) { option in
                menuButton(option)
            }
        } label: {
            HStack(spacing: 4) {
                Text(moreIsSelected ? StationCatalog.station(selected).shortName : "More")
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(moreIsSelected ? Color.white : Color.primary)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background {
                if moreIsSelected {
                    Capsule()
                        .fill(Color.accentColor)
                        .matchedGeometryEffect(id: "selected-pill", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(moreIsSelected
            ? "More destinations, selected \(StationCatalog.station(selected).shortName)"
            : "More destinations")
        .accessibilityIdentifier("more-destinations")
    }

    private func menuButton(_ option: DestinationOption) -> some View {
        Button { select(option.destination) } label: {
            if option.destination == selected {
                Label(option.label, systemImage: "checkmark")
            } else {
                Text(option.label)
            }
        }
    }
}

// MARK: - Board

/// Loading / offline / no trains / trains, plus the offline banner and freshness footer.
/// A hidden skeleton of the full trains layout sits behind the state area so loading,
/// no-trains and offline reserve the same height and the Favorites section never moves.
private struct BoardContent: View {
    let model: BoardModel
    let now: Date
    let liveActivities: LiveActivityController
    let startLiveActivity: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let board = model.board(now: now) {
                if model.errorMessage != nil, let fetchedAt = model.lastFetchAt {
                    OfflineBanner(age: now.timeIntervalSince(fetchedAt))
                }
                ZStack(alignment: .top) {
                    skeleton.hidden().accessibilityHidden(true)
                    if board.trains.isEmpty {
                        VStack(spacing: 12) {
                            stripAloneCard
                            NoTrainsState(destination: StationCatalog.station(model.trip.destination))
                        }
                    } else {
                        trainsLayout(
                            next: board.trains[0],
                            following: board.trains.count > 1 ? board.trains[1] : nil,
                            later: Array(board.trains.dropFirst(2).prefix(2)),
                            skeleton: false
                        )
                    }
                }
                FreshnessFooter(board: board, now: now)
            } else if let error = model.errorMessage {
                ZStack(alignment: .top) {
                    skeleton.hidden().accessibilityHidden(true)
                    VStack(spacing: 12) {
                        stripAloneCard
                        OfflineState(message: error, isRetrying: model.isLoading) {
                            Task { await model.refresh() }
                        }
                    }
                }
            } else {
                ZStack(alignment: .top) {
                    skeleton.hidden().accessibilityHidden(true)
                    VStack(spacing: 12) {
                        stripAloneCard
                        ProgressView("Loading trains…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .accessibilityIdentifier("state-loading")
                    }
                }
            }
        }
    }

    /// The full trains layout with dummy trains: reserves the trains-state height.
    private var skeleton: some View {
        trainsLayout(next: .dummy(now: now), following: .dummy(now: now), later: [.dummy(now: now), .dummy(now: now)], skeleton: true)
    }

    /// Without a next card the strip is normally hidden; while an activity is active (or
    /// erroring) it still renders alone so Stop stays reachable.
    @ViewBuilder
    private var stripAloneCard: some View {
        if liveActivities.activeTrip != nil || liveActivities.errorMessage != nil {
            LiveActivityStrip(controller: liveActivities, trip: model.trip, start: startLiveActivity)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    /// Next card (with the Live Activity strip), following card or placeholder, Later box.
    /// The skeleton renders the same layout with dummy trains and no accessibility content.
    @ViewBuilder
    private func trainsLayout(next: TrainArrival, following: TrainArrival?, later: [TrainArrival], skeleton: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                TrainInfo(train: next, now: now, prominence: .next)
                    .padding(16)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(next.spokenDescription(prefix: "Next train", at: now))
                    .accessibilityIdentifier(skeleton ? "skeleton-next-train" : "next-train")
                Divider()
                LiveActivityStrip(controller: liveActivities, trip: model.trip, start: startLiveActivity, recordsErrors: !skeleton)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if let following {
                TrainCard(train: following, now: now, prominence: .following)
            } else {
                ZStack {
                    TrainCard(train: .dummy(now: now), now: now, prominence: .following)
                        .hidden()
                    Text("Only one train in PATH's feed right now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .accessibilityIdentifier(skeleton ? "skeleton-following-placeholder" : "following-train-placeholder")
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            laterBox(later, skeleton: skeleton)
        }
    }

    /// Always exactly two row slots; missing rows are invisible same-size placeholders so the
    /// box — and everything below it — never moves. Empty feed: a message across the box.
    private func laterBox(_ later: [TrainArrival], skeleton: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Later")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            ForEach(0..<2, id: \.self) { index in
                if index > 0 { Divider().opacity(index < later.count ? 1 : 0) }
                if index < later.count {
                    ZStack(alignment: .topLeading) {
                        LaterTrainRow(train: .dummy(now: now), now: now, index: index + 20)
                            .hidden()
                        LaterTrainRow(train: later[index], now: now, index: index)
                    }
                } else {
                    LaterTrainRow(train: .dummy(now: now), now: now, index: index + 10)
                        .hidden()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if later.isEmpty, !skeleton {
                Text("No later trains in the feed yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)
                    .accessibilityIdentifier("later-trains-placeholder")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(skeleton ? "skeleton-later-trains" : "later-trains")
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

// MARK: - Live Activity strip

/// The compact Live Activity row inside the next-train card: follow / on Lock Screen / switch,
/// or the Settings hint when activities are off.
struct LiveActivityStrip: View {
    let controller: LiveActivityController
    let trip: Trip
    let start: () -> Void
    var recordsErrors = true

    @ScaledMetric(relativeTo: .subheadline) private var rowHeight = 32
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    @Environment(FeedbackCenter.self) private var feedback: FeedbackCenter?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        leading
                        HStack(spacing: 8) { trailing }
                    }
                } else {
                    HStack(spacing: 8) {
                        leading
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        HStack(spacing: 6) { trailing }
                            .fixedSize()
                            .layoutPriority(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: rowHeight)
            if let error = controller.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("live-activity-error")
            }
        }
        .onChange(of: controller.errorMessage, initial: true) { _, error in
            if recordsErrors, let error { feedback?.record("Live Activity: \(error)") }
        }
    }

    @ViewBuilder
    private var leading: some View {
        if let active = controller.activeTrip {
            if active.sameRoute(as: trip) {
                statusLabel {
                    if let endsAt = controller.endsAt {
                        Text("On Lock Screen · until \(Text(endsAt, style: .time))")
                    } else {
                        Text("On Lock Screen")
                    }
                }
            } else {
                statusLabel { Text("On Lock Screen: \(active.title)") }
            }
        } else if controller.areActivitiesEnabled {
            Button(action: start) {
                Label("Follow on Lock Screen", systemImage: "platter.filled.bottom.iphone")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
            .accessibilityHint("Shows the next trains on the Lock Screen and in the Dynamic Island.")
            .accessibilityIdentifier("live-activity-button")
        } else {
            Text("Lock Screen updates are off")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("live-activity-disabled")
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if let active = controller.activeTrip {
            if active.sameRoute(as: trip) {
                stopButton
            } else {
                Button(action: start) {
                    Text("Switch")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Switch to this trip")
                .accessibilityHint("Shows \(trip.title) on the Lock Screen instead.")
                .accessibilityIdentifier("live-activity-button")
                stopButton
            }
        } else if controller.areActivitiesEnabled {
            EmptyView()
        } else {
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("live-activity-settings")
        }
    }

    private func statusLabel(_ text: () -> some View) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            text()
                .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("live-activity-status")
    }

    private var stopButton: some View {
        Button(role: .destructive) {
            Task { await controller.stop() }
        } label: {
            Text("Stop")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("live-activity-stop")
    }
}

// MARK: - Banners

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
