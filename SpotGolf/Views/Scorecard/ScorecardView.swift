import SwiftUI

/// The round as a paper scorecard for the tee the player picked: the row titles on the left
/// and the total on the right stay put, and the holes between them scroll sideways. Each
/// nine ends in a subtotal, "Out" then "In". See plans/2026-10-09-scorecard.md.
struct ScorecardView: View {
    let roundID: UUID
    /// The edit button under a hole: the map edits that hole.
    let editHole: (Int) -> Void

    @Environment(PhoneServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    /// Compact in landscape, where everything is made shorter to fit every row.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isCompact: Bool { verticalSizeClass == .compact }
    private var rowHeight: CGFloat { isCompact ? 28 : 36 }

    private var round: Round? {
        services.roundStore.round(roundID)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let round {
                header(round)
                Divider()
                ScrollView(.vertical) {
                    card(round)
                        .padding(.horizontal, 12)
                        .padding(.vertical, isCompact ? 6 : 12)
                }
            }
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Text("Close")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, isCompact ? 0 : 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .padding(.horizontal, 16)
            .padding(.vertical, isCompact ? 4 : 12)
            .accessibilityIdentifier("CloseScorecard")
        }
    }

    // MARK: - Header

    private func header(_ round: Round) -> some View {
        let toPar = HoleOverview.toPar(round).map(HoleOverview.toParText)
        let date = round.date.formatted(date: .abbreviated, time: .omitted)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: isCompact ? 0 : 4) {
                Text(round.course.name)
                    .font(isCompact ? .headline : .title3)
                    .fontWeight(.bold)
                    .lineLimit(1)
                Group {
                    if let tee = round.courseSelection.teeName {
                        Text("\(tee) Tees · \(date)", comment: "The scorecard's tee and the day the round was played")
                    } else {
                        Text(date)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(round.allStrokes.count)")
                    .font(isCompact ? .title : .largeTitle)
                    .fontWeight(.bold)
                    .monospacedDigit()
                if let toPar {
                    Text(toPar)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Total score")
            .accessibilityValue(toPar.map { "\(round.allStrokes.count), \($0)" } ?? "\(round.allStrokes.count)")
            .accessibilityIdentifier("ScorecardTotal")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isCompact ? 4 : 12)
    }

    // MARK: - Card

    private static let holeWidth: CGFloat = 40
    private static let subtotalWidth: CGFloat = 48
    private static let titleWidth: CGFloat = 72

    private func rows(_ round: Round) -> [ScorecardRow] {
        let hasYards = round.courseSelection.teeName != nil
        return ScorecardRow.allCases.filter { $0 != .yards || hasYards }
    }

    private func card(_ round: Round) -> some View {
        let rows = rows(round)
        let holeCount = round.lastHoleIndex + 1
        let nines = stride(from: 0, to: holeCount, by: 9).map { $0..<min($0 + 9, holeCount) }
        return HStack(spacing: 0) {
            column(rows, width: Self.titleWidth, isHeader: true) { row in
                titleCell(row)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(nines.enumerated()), id: \.offset) { nine, holes in
                        ForEach(holes, id: \.self) { index in
                            column(rows, width: Self.holeWidth) { row in
                                holeCell(row, index: index, round: round)
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("ScorecardHole-\(index + 1)")
                        }
                        column(rows, width: Self.subtotalWidth, isHeader: true) { row in
                            subtotalCell(row, title: nine == 0 ? "Out" : "In", holes: Array(holes), round: round)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(nine == 0 ? "ScorecardOut" : "ScorecardIn")
                    }
                }
            }
            column(rows, width: Self.subtotalWidth, isHeader: true) { row in
                subtotalCell(row, title: "Tot", holes: Array(0..<holeCount), round: round)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ScorecardTot")
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.4), lineWidth: 1))
    }

    /// One column of cells, one per row, with lines between them.
    private func column(_ rows: [ScorecardRow], width: CGFloat, isHeader: Bool = false,
                        @ViewBuilder cell: @escaping (ScorecardRow) -> some View) -> some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.self) { row in
                // An empty cell still takes its place in the column
                ZStack {
                    Color.clear
                    cell(row)
                }
                .frame(width: width, height: rowHeight)
                    .background(row == .hole || isHeader ? Color(.tertiarySystemBackground) : Color.clear)
                    .overlay(alignment: .bottom) {
                        if row != rows.last {
                            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                        }
                    }
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 1)
        }
    }

    private func titleCell(_ row: ScorecardRow) -> some View {
        Text(row.title)
            .font(.caption)
            .fontWeight(.semibold)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private func holeCell(_ row: ScorecardRow, index: Int, round: Round) -> some View {
        let hole = round.hole(at: index)
        let par = round.courseHole(at: index)?.par
        let played = !hole.strokes.isEmpty
        switch row {
        case .hole:
            Text("\(index + 1)")
                .font(.subheadline)
                .fontWeight(.semibold)
        case .yards:
            Text(round.courseSelection.yards(holeIndex: index).map(String.init) ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .par:
            Text(par.map(String.init) ?? "")
                .font(.subheadline)
        case .score:
            if played {
                ScoreMark(score: hole.strokeCount, par: par)
            }
        case .putts:
            if let putts = hole.stats?.putts {
                Text("\(putts)")
                    .font(.subheadline)
            }
        case .fairway:
            if let fairway = hole.stats?.fairway {
                checkbox(fairway)
            }
        case .green:
            if let green = hole.stats?.green {
                checkbox(green)
            }
        case .edit:
            Button {
                dismiss()
                editHole(index)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit hole \(index + 1)")
            .accessibilityIdentifier("ScorecardEdit-\(index + 1)")
        }
    }

    private func checkbox(_ isHit: Bool) -> some View {
        Image(systemName: isHit ? "checkmark.square.fill" : "square")
            .font(.subheadline)
            .foregroundStyle(isHit ? Color.green : Color.secondary)
            .accessibilityLabel(isHit ? "Hit" : "Missed")
    }

    /// A subtotal of `holes`: the yards, par, and score added up, and the fairways and greens hit
    /// out of the ones played.
    @ViewBuilder
    private func subtotalCell(_ row: ScorecardRow, title: LocalizedStringKey, holes: [Int], round: Round) -> some View {
        let played = holes.map(round.hole(at:)).filter { !$0.strokes.isEmpty }
        let stats = played.compactMap(\.stats)
        switch row {
        case .hole:
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
        case .yards:
            let yards = holes.compactMap { round.courseSelection.yards(holeIndex: $0) }
            Text(yards.isEmpty ? "" : "\(yards.reduce(0, +))")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .par:
            let pars = holes.compactMap { round.courseHole(at: $0)?.par }
            Text(pars.isEmpty ? "" : "\(pars.reduce(0, +))")
                .font(.subheadline)
                .fontWeight(.semibold)
        case .score:
            Text(played.isEmpty ? "" : "\(played.reduce(0) { $0 + $1.strokeCount })")
                .font(.subheadline)
                .fontWeight(.bold)
        case .putts:
            Text(stats.isEmpty ? "" : "\(stats.reduce(0) { $0 + $1.putts })")
                .font(.subheadline)
                .fontWeight(.semibold)
        case .fairway:
            let chances = stats.compactMap(\.fairway)
            Text(chances.isEmpty ? "" : "\(chances.filter { $0 }.count)/\(chances.count)")
                .font(.caption)
                .fontWeight(.semibold)
        case .green:
            Text(stats.isEmpty ? "" : "\(stats.filter(\.green).count)/\(stats.count)")
                .font(.caption)
                .fontWeight(.semibold)
        case .edit:
            Color.clear
        }
    }
}

/// The scorecard's rows, top to bottom.
private enum ScorecardRow: CaseIterable {
    case hole, yards, par, score, putts, fairway, green, edit

    var title: LocalizedStringKey {
        switch self {
        case .hole: "Hole"
        case .yards: "Yards"
        case .par: "Par"
        case .score: "Score"
        case .putts: "Putts"
        case .fairway: "Fairway"
        case .green: "Green"
        case .edit: "Edit"
        }
    }
}

/// A hole's score marked as on a paper card: a circle under par, a square over it.
private struct ScoreMark: View {
    let score: Int
    let par: Int?

    var body: some View {
        let diff = par.map { score - $0 } ?? 0
        Text("\(score)")
            .font(.subheadline)
            .fontWeight(.semibold)
            .frame(width: 26, height: 26)
            .overlay {
                if diff < 0 {
                    Circle().stroke(Color.red, lineWidth: 1.5)
                } else if diff > 0 {
                    Rectangle().stroke(Color.primary.opacity(0.6), lineWidth: 1.5)
                }
            }
    }
}
