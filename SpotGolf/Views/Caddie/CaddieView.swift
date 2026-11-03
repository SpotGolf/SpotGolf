import SwiftUI

/// The Caddie tab: how far the player hits each club in the bag, in bag order, the putter left
/// out. Each club starts from the bag's distance and moves toward the player's shots. See
/// plans/2026-11-02-caddie-club-distances.md, section 3.
struct CaddieView: View {
    @Environment(PhoneServices.self) private var services

    var body: some View {
        let distances = services.caddie.distances
        Group {
            if distances.isEmpty {
                ContentUnavailableView {
                    Label("No Clubs", image: "DriverHead")
                } description: {
                    Text("Add clubs to your golf bag in Settings to see how far you hit each one.")
                }
            } else {
                // One scale for every row, so the bars step down through the bag
                let scale = RangeLine.scale(reaching: distances.map(\.distance.high).max() ?? 0)
                List {
                    Section {
                        ForEach(distances, id: \.club) { entry in
                            ClubDistanceRow(club: entry.club, distance: entry.distance, scale: scale)
                        }
                    } footer: {
                        Text("Starts from your golf bag's distances and moves toward your own shots: each shot's spot to the next. The bar shows where about two in three shots land. Putts, thumbs-down shots, shots from the Green Zone and shots with penalty strokes are left out.")
                    }
                }
            }
        }
        .navigationTitle("Caddie")
    }
}

/// One club: its name and shot count, its average, and a line across the row with its range.
private struct ClubDistanceRow: View {
    let club: Club
    let distance: ClubDistance
    /// The yards at the line's right end.
    let scale: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(club.name)
                        .font(.headline)
                    Text(shotCount)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(distance.average) yd")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
            }
            RangeLine(distance: distance, scale: scale)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
        .accessibilityIdentifier("Caddie-\(club.id)")
    }

    private var shotCount: String {
        distance.shots == 0 ? String(localized: "No shots yet") : String(localized: "\(distance.shots) shots")
    }

    private var accessibilityText: String {
        [club.name, String(localized: "\(distance.average) yd"),
         String(localized: "\(distance.low) to \(distance.high) yd"), shotCount].joined(separator: ", ")
    }
}

/// A line across the row from 0 to `scale` yards, with a tick every 50, and on it a bar from
/// `low` to `high` with a dot at the average and each end's yards under it. A club with no shots
/// shows its starting estimate in a lighter color.
private struct RangeLine: View {
    let distance: ClubDistance
    let scale: Int

    /// Yards between ticks, and what the scale rounds up to.
    static let tickYards = 50

    /// The scale for a line that must reach `yards`: the next tick at or past it.
    static func scale(reaching yards: Int) -> Int {
        max((yards + tickYards - 1) / tickYards, 1) * tickYards
    }

    private let lineHeight: CGFloat = 3
    private let tickHeight: CGFloat = 9
    private let barHeight: CGFloat = 8
    private let dotSize: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let middle = dotSize / 2
            let lowX = x(distance.low, width)
            let highX = x(distance.high, width)
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: width, height: lineHeight)
                    .position(x: width / 2, y: middle)
                ForEach(Array(stride(from: Self.tickYards, to: scale, by: Self.tickYards)), id: \.self) { yards in
                    Capsule()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 1.5, height: tickHeight)
                        .position(x: x(yards, width), y: middle)
                }
                Capsule()
                    .fill(Color.accentColor.opacity(hasShots ? 0.35 : 0.15))
                    .frame(width: max(highX - lowX, barHeight), height: barHeight)
                    .position(x: (lowX + highX) / 2, y: middle)
                Circle()
                    .fill(Color.accentColor.opacity(hasShots ? 1 : 0.45))
                    .frame(width: dotSize, height: dotSize)
                    .position(x: x(distance.average, width), y: middle)
                // Each end's number reaches out from its end, so the two never overlap
                Text(verbatim: "\(distance.low)")
                    .alignmentGuide(.leading) { -max(0, lowX - $0.width) }
                    .alignmentGuide(.top) { _ in -(dotSize + 2) }
                Text(verbatim: "\(distance.high)")
                    .alignmentGuide(.leading) { -min(width - $0.width, highX) }
                    .alignmentGuide(.top) { _ in -(dotSize + 2) }
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .frame(height: dotSize + 20)
    }

    private var hasShots: Bool {
        distance.shots > 0
    }

    /// Where `yards` falls across the line.
    private func x(_ yards: Int, _ width: CGFloat) -> CGFloat {
        min(max(CGFloat(yards) / CGFloat(scale), 0), 1) * width
    }
}
