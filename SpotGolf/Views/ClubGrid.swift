import SwiftUI

/// Clubs as a grid of buttons with their short names, filled when selected. Up to 14 fit in
/// three rows at phone width, so a bag never scrolls.
struct ClubGrid: View {
    let clubs: [Club]
    let isSelected: (Club) -> Bool
    var isEnabled: (Club) -> Bool = { _ in true }
    let tap: (Club) -> Void

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(clubs) { club in
                clubButton(club)
            }
        }
    }

    private func clubButton(_ club: Club) -> some View {
        ChoiceButton(isSelected: isSelected(club), isEnabled: isEnabled(club)) {
            tap(club)
        } label: {
            Text(club.shortName)
                .font(.body.monospacedDigit())
        }
        .accessibilityLabel(club.name)
        .accessibilityIdentifier("Club-\(club.id)")
    }
}
