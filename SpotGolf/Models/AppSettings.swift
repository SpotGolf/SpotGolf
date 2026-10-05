import Foundation

struct AppSettings: Codable, Equatable {
    var stationaryThreshold: TimeInterval

    init(stationaryThreshold: TimeInterval = 30) {
        self.stationaryThreshold = stationaryThreshold
    }

    static let `default` = AppSettings()
}
