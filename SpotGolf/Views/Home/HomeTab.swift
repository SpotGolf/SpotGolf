import SwiftUI

/// The tabs along the bottom of the home screen, left to right. See
/// plans/2026-11-02-caddie-club-distances.md, section 1.
enum HomeTab: CaseIterable, Identifiable {
    case rounds
    case caddie
    case newRound
    case puttSharing
    case settings

    var id: Self { self }

    /// The icon, filled while the tab is active. SF Symbols has no scorecard, driver or putter,
    /// so those are our own. The driver is always filled, so its face lines show.
    func icon(isActive: Bool) -> Image {
        switch self {
        case .rounds: Image(isActive ? "ScorecardFill" : "Scorecard")
        case .caddie: Image("DriverHead")
        case .newRound: Image(systemName: "plus.circle.fill")
        case .puttSharing: Image(isActive ? "PutterHeadFill" : "PutterHead")
        case .settings: Image(systemName: isActive ? "gearshape.fill" : "gearshape")
        }
    }

    /// For VoiceOver; the bar shows no labels. `hasRound` is a round in progress.
    func label(hasRound: Bool) -> LocalizedStringKey {
        switch self {
        case .rounds: "Rounds"
        case .caddie: "Caddie"
        case .newRound: hasRound ? "Current Round" : "New Round"
        case .puttSharing: "Putt Data Sharing"
        case .settings: "Settings"
        }
    }
}
