import SwiftUI

/// A button in a set of choices: filled when selected, outlined in gray otherwise. The club
/// grid and the spot sheet's penalty buttons share it.
struct ChoiceButton<Label: View>: View {
    let isSelected: Bool
    var isEnabled = true
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        let button = Button(action: action) {
            label()
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        if isSelected {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered).tint(.gray)
        }
    }
}
