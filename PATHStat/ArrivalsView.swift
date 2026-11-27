import PATHKit
import SwiftUI

struct ArrivalsView: View {
    @State private var model = ArrivalsModel()

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                List {
                    statusSection(now: context.date)
                    ForEach(model.directions, id: \.self) { direction in
                        directionSection(direction, now: context.date)
                    }
                }
            }
            .navigationTitle(model.stationInfo.name)
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .overlay {
                if model.snapshot == nil && model.isLoading {
                    ProgressView("Loading arrivals…")
                }
            }
        }
    }

    @ViewBuilder
    private func statusSection(now: Date) -> some View {
        let freshness = model.freshness(now: now)
        if model.errorMessage != nil || isStale(freshness) {
            Section {
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                if case .stale(let age) = freshness {
                    Label("Data is \(Int(age / 60)) min old", systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func isStale(_ freshness: Freshness) -> Bool {
        if case .stale = freshness { return true }
        return false
    }

    @ViewBuilder
    private func directionSection(_ direction: Direction, now: Date) -> some View {
        let board = model.board(direction, now: now)
        Section(direction == .toNY ? "To New York" : "To New Jersey") {
            if let board, !board.trains.isEmpty {
                ForEach(board.trains.prefix(4)) { train in
                    TrainRow(train: train, now: now)
                }
            } else if model.snapshot != nil {
                Text("No trains listed").foregroundStyle(.secondary)
            }
        }
    }
}

private struct TrainRow: View {
    let train: TrainArrival
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(train.lineColors, id: \.self) { hex in
                    Capsule().fill(Color(hex: hex)).frame(width: 6, height: 32)
                }
            }
            VStack(alignment: .leading) {
                Text(train.headsign).font(.headline)
                Text(train.line?.displayName ?? "PATH").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            let minutes = train.minutesRemaining(at: now)
            Text(minutes == 0 ? "Now" : "\(minutes) min")
                .font(.title3.monospacedDigit().weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }
}

private extension Color {
    init(hex: String) {
        let value = UInt64(hex.prefix(6), radix: 16) ?? 0x888888
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

#Preview {
    ArrivalsView()
}
