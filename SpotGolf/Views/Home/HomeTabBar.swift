import SwiftUI

/// The bar fixed at the bottom of the home screen: flat icon buttons with no labels and no
/// glass, the active one in the accent color. `accessory`, such as the New Round tab's search
/// field, goes above the buttons, so the bar grows taller and the buttons stay where they are.
/// See plans/2026-11-02-caddie-club-distances.md, sections 1 and 2.
struct HomeTabBar<Accessory: View>: View {
    let selection: HomeTab
    /// A round in progress: starting, active or ending.
    let hasRound: Bool
    /// False without a paired watch, while no round is in progress.
    let canStartRound: Bool
    /// False while the keyboard is up: the buttons stay under it, and only the accessory rides on it.
    let showsButtons: Bool
    let onSelect: (HomeTab) -> Void
    @ViewBuilder let accessory: Accessory

    @ScaledMetric(relativeTo: .body) private var iconHeight: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var newRoundHeight: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            accessory
            if showsButtons {
                buttons
            }
        }
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var buttons: some View {
        HStack(spacing: 0) {
            ForEach(HomeTab.allCases) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    tab.icon(isActive: tab == selection)
                        .resizable()
                        .scaledToFit()
                        .frame(height: tab == .newRound ? newRoundHeight : iconHeight)
                        .frame(maxWidth: .infinity, minHeight: newRoundHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(color(of: tab))
                .disabled(tab == .newRound && !hasRound && !canStartRound)
                .accessibilityLabel(tab.label(hasRound: hasRound))
                .accessibilityAddTraits(tab == selection ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func color(of tab: HomeTab) -> Color {
        if tab == .newRound && !hasRound && !canStartRound {
            return Color(.tertiaryLabel)
        }
        return tab == selection ? .accentColor : .secondary
    }
}
