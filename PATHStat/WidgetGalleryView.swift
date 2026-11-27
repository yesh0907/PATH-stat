import PATHKit
import SwiftUI
import WidgetKit

/// `-WidgetGallery <live|stale|offline|unavailable|noTrains>`: renders the shared widget views
/// for every family at widget sizes, from fixed `WidgetTimeline` entries, for screenshots.
struct WidgetGalleryView: View {
    let state: WidgetSampleState
    /// Fixed at launch so the countdowns tick from a stable entry date.
    @State private var now = Date.now

    private struct Tile: Identifiable {
        let family: WidgetFamily
        let name: String
        let size: CGSize?
        var id: String { name }
    }

    private let tiles: [Tile] = [
        Tile(family: .systemSmall, name: "systemSmall", size: CGSize(width: 170, height: 170)),
        Tile(family: .systemMedium, name: "systemMedium", size: CGSize(width: 364, height: 170)),
        Tile(family: .accessoryRectangular, name: "accessoryRectangular", size: CGSize(width: 172, height: 76)),
        Tile(family: .accessoryCircular, name: "accessoryCircular", size: CGSize(width: 76, height: 76)),
        Tile(family: .accessoryInline, name: "accessoryInline", size: nil),
    ]

    var body: some View {
        let entry = state.entry(now: now)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Widget gallery · \(state.rawValue)")
                    .font(.headline)
                ForEach(tiles) { tile in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tile.name)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        render(tile, entry: entry)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("widget-\(tile.name)")
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        .accessibilityIdentifier("widget-gallery")
    }

    @ViewBuilder
    private func render(_ tile: Tile, entry: WidgetEntryState) -> some View {
        let view = NextTrainWidgetView(state: entry, family: tile.family, rendersInApp: true)
        switch tile.family {
        case .systemSmall, .systemMedium:
            view
                .padding(16)
                .frame(width: tile.size?.width, height: tile.size?.height)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        case .accessoryInline:
            // Lock Screen inline widgets are a single line of text above the clock.
            view
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.85), in: Capsule())
        default:
            view
                .foregroundStyle(.white)
                .padding(tile.family == .accessoryCircular ? 4 : 8)
                .frame(width: tile.size?.width, height: tile.size?.height)
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: tile.family == .accessoryCircular ? 38 : 12, style: .continuous))
                .environment(\.colorScheme, .dark)
        }
    }
}

#Preview("Live") { WidgetGalleryView(state: .live) }
#Preview("Stale") { WidgetGalleryView(state: .stale) }
#Preview("Offline") { WidgetGalleryView(state: .offline) }
#Preview("Unavailable") { WidgetGalleryView(state: .unavailable) }
#Preview("No trains") { WidgetGalleryView(state: .noTrains) }
