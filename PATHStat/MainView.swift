import CoreLocation
import PATHKit
import SwiftUI

/// The main screen: station, destination, and the next trains for the current trip.
struct MainView: View {
    let model: BoardModel
    let location: LocationService
    /// Live mode only: shares fetched snapshots with the widget.
    var widgetSync: WidgetSync?

    /// Feed refresh cadence while the screen is visible and the app is active.
    static let refreshInterval: Duration = .seconds(20)

    @Environment(\.scenePhase) private var scenePhase
    @State private var showingStationPicker = false

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
                    remove: model.removeFavorite
                )
                LiveActivityPlaceholder()
            }
            .padding()
        }
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { location.refresh() }
            if phase == .background { widgetSync?.didEnterBackground() }
        }
        .onChange(of: model.lastFetchAt) { _, _ in
            // `lastFetchAt` only changes on a successful fetch.
            if let snapshot = model.snapshot { widgetSync?.didFetch(snapshot) }
        }
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
        }
    }

    private var origin: Station { StationCatalog.station(model.trip.origin) }

    // MARK: Header

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
    }
}

private struct OfflineState: View {
    let message: String
    let isRetrying: Bool
    let retry: () -> Void

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
    }
}

private struct OfflineBanner: View {
    let age: TimeInterval

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
    }
}

private struct FreshnessFooter: View {
    let board: DepartureBoard
    let now: Date

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

/// Phase-4 hook: Live Activities aren't implemented yet.
private struct LiveActivityPlaceholder: View {
    var body: some View {
        VStack(spacing: 4) {
            Button {} label: {
                Label("Start Live Activity", systemImage: "dot.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(true)
            .accessibilityHint("Coming soon")
            .accessibilityIdentifier("live-activity-button")
            Text("Coming soon")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Previews

#Preview("Trains") {
    let environment = Scenario.trains.makeEnvironment()
    MainView(model: environment.model, location: environment.location)
}

#Preview("Near 23rd St") {
    let environment = Scenario.trains.makeEnvironment(location: StationCatalog.station(.twentyThirdStreet).location)
    MainView(model: environment.model, location: environment.location)
}

#Preview("Loading") {
    let environment = Scenario.loading.makeEnvironment()
    MainView(model: environment.model, location: environment.location)
}

#Preview("No trains") {
    let environment = Scenario.noTrains.makeEnvironment()
    MainView(model: environment.model, location: environment.location)
}

#Preview("Offline") {
    let environment = Scenario.offline.makeEnvironment()
    MainView(model: environment.model, location: environment.location)
}

#Preview("Offline with data") {
    let environment = Scenario.offlineWithData.makeEnvironment()
    MainView(model: environment.model, location: environment.location)
}

#Preview("Location denied") {
    let environment = Scenario.locationDenied.makeEnvironment()
    MainView(model: environment.model, location: environment.location)
}
