import Foundation

/// A permission the watch needs to record a round. Location, motion and health are shared
/// with the iPhone app and asked for there; the microphone is the watch's own and is asked
/// for on the watch.
enum AppPermission: String, Codable, CaseIterable {
    /// GPS fixes.
    case location
    /// Swing detection.
    case motion
    /// Saving the workout that keeps the app running and turns on swing data.
    case health
    /// Hearing the putter hit the ball on the green.
    case microphone

    /// The name the system uses for it.
    var title: String {
        switch self {
        case .location: String(localized: "Location")
        case .motion: String(localized: "Motion & Fitness")
        case .health: String(localized: "Health")
        case .microphone: String(localized: "Microphone")
        }
    }

    /// The watch shows the prompt itself; the others are granted on the phone.
    var isAskedOnWatch: Bool {
        self == .microphone
    }
}

enum PermissionState: Equatable {
    /// The system prompt has not been shown.
    case notAsked
    /// The user said no, or it is turned off for every app. The prompt can't be shown again.
    case denied
    case granted
}
