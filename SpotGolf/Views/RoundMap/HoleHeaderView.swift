import SwiftUI

/// Every hole as a circle, with a back button and the score box on top at each end. The score
/// box opens the scorecard.
/// The shown hole's par and distance sit underneath.
struct HoleHeaderView: View {
    let round: Round
    let shownHoleIndex: Int
    /// A tap on a hole's circle.
    let selectHole: (Int) -> Void
    let openScorecard: () -> Void

    @Environment(PhoneServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let holeCount = round.courseSelection.orderedHoles.count
        VStack(spacing: 6) {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(0..<holeCount, id: \.self) { index in
                                holeCircle(index)
                                    .id(index)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    // The first and last holes can scroll to the center of the display
                    .contentMargins(.horizontal, max(0, geometry.size.width / 2 - 18), for: .scrollContent)
                    .mask(holeFadeMask)
                    .onAppear {
                        proxy.scrollTo(shownHoleIndex, anchor: .center)
                    }
                    .onChange(of: shownHoleIndex) {
                        withAnimation {
                            proxy.scrollTo(shownHoleIndex, anchor: .center)
                        }
                    }
                }
            }
            .frame(height: 40)
            .overlay(alignment: .leading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .fontWeight(.semibold)
                        .frame(width: 44, height: 40)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.bar))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .accessibilityLabel("Back")
            }
            .overlay(alignment: .trailing) {
                scoreBox
                    .padding(.trailing, 12)
            }

            if let summary = HoleOverview.summary(round, holeIndex: shownHoleIndex,
                                                  from: services.locationManager.lastLocation) {
                Text(summary)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .accessibilityIdentifier("HoleSummary")
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    /// Hides the holes behind the back button and the score box, with a small gap,
    /// and fades them out as they come near either one.
    private var holeFadeMask: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 64)  // back button (12 + 44) and a gap
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: 32)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 32)
            Color.clear.frame(width: 72)  // score box (52 + 12) and a gap
        }
    }

    /// The round's total strokes, and how they compare to par on the finished holes.
    private var scoreBox: some View {
        let total = round.allStrokes.count
        let toPar = HoleOverview.toPar(round).map(HoleOverview.toParText)
        return Button(action: openScorecard) {
            VStack(spacing: 0) {
                Text("\(total)")
                    .font(.headline)
                    .monospacedDigit()
                if let toPar {
                    Text(toPar)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 52, height: 40)
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 8).fill(.bar))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.5), lineWidth: 1))
        .accessibilityLabel("Score")
        .accessibilityValue(toPar.map { "\(total), \($0)" } ?? "\(total)")
        .accessibilityIdentifier("ScoreBox")
    }

    private func holeCircle(_ index: Int) -> some View {
        let isShown = index == shownHoleIndex
        let isPlayed = index < round.holes.count && !round.holes[index].strokes.isEmpty
        return Button {
            selectHole(index)
        } label: {
            Text("\(index + 1)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(isShown ? Color.white : Color.primary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(isShown ? Color.green : isPlayed ? Color.green.opacity(0.18) : Color.clear))
                .overlay(Circle().stroke(isShown ? Color.green : Color.secondary.opacity(0.5), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hole \(index + 1)")
        .accessibilityAddTraits(isShown ? .isSelected : [])
    }
}
