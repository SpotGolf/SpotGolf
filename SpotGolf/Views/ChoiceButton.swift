import SwiftUI

/// A button in a set of choices: filled when selected, outlined in gray otherwise. The club
/// grid uses it.
struct ChoiceButton<Label: View>: View {
    let isSelected: Bool
    var isEnabled = true
    var minHeight: CGFloat = 36
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        let button = Button(action: action) {
            label()
                .frame(maxWidth: .infinity, minHeight: minHeight)
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
