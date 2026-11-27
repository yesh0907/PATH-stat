import PATHKit
import SwiftUI

/// Saved trips; one tap selects, long-press (or the VoiceOver action) removes.
struct FavoritesSection: View {
    let favorites: [Trip]
    let current: Trip
    let select: (Trip) -> Void
    let remove: (Trip) -> Void
    var startLiveActivity: ((Trip) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Favorites")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            if favorites.isEmpty {
                Text("Tap the star next to a trip to save it here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(favorites.enumerated()), id: \.element.id) { index, trip in
                        if index > 0 { Divider().padding(.leading, 16) }
                        row(trip)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("favorites-section")
    }

    private func row(_ trip: Trip) -> some View {
        let isCurrent = trip.sameRoute(as: current)
        return Button { select(trip) } label: {
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.title).foregroundStyle(.primary)
                    if trip.name != nil {
                        Text(Trip(origin: trip.origin, destination: trip.destination).title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let startLiveActivity {
                Button { startLiveActivity(trip) } label: {
                    Label("Start Live Activity", systemImage: "dot.radiowaves.left.and.right")
                }
            }
            Button(role: .destructive) { remove(trip) } label: {
                Label("Remove from Favorites", systemImage: "star.slash")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle(trip))
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Start Live Activity") { startLiveActivity?(trip) }
        .accessibilityAction(named: "Remove from Favorites") { remove(trip) }
        .accessibilityIdentifier("favorite-\(trip.id)")
    }

    private func accessibilityTitle(_ trip: Trip) -> String {
        let route = "\(StationCatalog.station(trip.origin).name) to \(StationCatalog.station(trip.destination).name)"
        return trip.name.map { "\($0), \(route)" } ?? route
    }
}
