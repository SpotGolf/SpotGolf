import Foundation

struct AppSettings: Codable, Equatable {
    var missedMarkGuessesEnabled: Bool
    var hapticEnabled: Bool
    var stationaryThreshold: TimeInterval

    init(missedMarkGuessesEnabled: Bool = true,
         hapticEnabled: Bool = true,
         stationaryThreshold: TimeInterval = 30) {
        self.missedMarkGuessesEnabled = missedMarkGuessesEnabled
        self.hapticEnabled = hapticEnabled
        self.stationaryThreshold = stationaryThreshold
    }

    static let `default` = AppSettings()
}
