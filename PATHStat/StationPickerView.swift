import CoreLocation
import PATHKit
import SwiftUI

/// Sheet listing every station, nearest first when location is known.
struct StationPickerView: View {
    let current: StationCode
    let location: CLLocation?
    let select: (StationCode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private struct Row: Identifiable {
        let station: Station
        let distance: CLLocationDistance?
        var id: StationCode { station.code }
    }

    private var rows: [Row] {
        let ordered: [Row] = if let location {
            StationCatalog.stations(nearest: location).map {
                // Closer than `Format.nearbyThreshold`, no distance is shown.
                Row(station: $0.station, distance: $0.distance >= Format.nearbyThreshold ? $0.distance : nil)
            }
        } else {
            StationCatalog.all.map { Row(station: $0, distance: nil) }
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return ordered }
        return ordered.filter { row in
            [row.station.name, row.station.shortName, row.station.code.rawValue].contains {
                $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            List(rows) { row in
                Button {
                    select(row.station.code)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.station.name).foregroundStyle(.primary)
                            LineDots(lines: row.station.lines)
                        }
                        Spacer(minLength: 8)
                        if let distance = row.distance {
                            Text(Format.distance(distance))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if row.station.code == current {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(for: row))
                .accessibilityAddTraits(row.station.code == current ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("station-\(row.station.code.rawValue)")
            }
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search stations")
            .navigationTitle("Stations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func label(for row: Row) -> String {
        var parts = [row.station.name]
        if let distance = row.distance { parts.append(Format.distance(distance, wide: true)) }
        parts.append(row.station.lines.map(\.displayName).joined(separator: ", "))
        return parts.joined(separator: ", ")
    }
}

#Preview("With location") {
    StationPickerView(current: .groveStreet, location: StationCatalog.station(.hoboken).location) { _ in }
}

#Preview("No location") {
    StationPickerView(current: .twentyThirdStreet, location: nil) { _ in }
}
