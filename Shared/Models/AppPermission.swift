import Foundation

/// A permission the watch needs to record a round.
enum AppPermission: String, Codable, CaseIterable {
    /// GPS fixes.
    case location
    /// Swing detection.
    case motion
    /// Saving the workout that keeps the app running and turns on swing data.
    case health

    /// The name the system uses for it.
    var title: String {
        switch self {
        case .location: "Location"
        case .motion: "Motion & Fitness"
        case .health: "Health"
        }
    }
}

enum PermissionState: Equatable {
    /// The system prompt has not been shown.
    case notAsked
    /// The user said no, or it is turned off for every app. The prompt can't be shown again.
    case denied
    case granted
}
