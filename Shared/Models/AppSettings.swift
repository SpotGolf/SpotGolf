import Foundation

struct AppSettings: Codable, Equatable {
    var missedMarkGuessesEnabled: Bool
    var stationaryThreshold: TimeInterval

    init(missedMarkGuessesEnabled: Bool = true,
         stationaryThreshold: TimeInterval = 30) {
        self.missedMarkGuessesEnabled = missedMarkGuessesEnabled
        self.stationaryThreshold = stationaryThreshold
    }

    static let `default` = AppSettings()
}
