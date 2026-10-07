import Foundation

struct AppSettings: Codable, Equatable {
    var stationaryThreshold: TimeInterval
    /// Uploads the pins the player sets, for other golfers on the same course.
    var sharePins: Bool

    init(stationaryThreshold: TimeInterval = 30, sharePins: Bool = true) {
        self.stationaryThreshold = stationaryThreshold
        self.sharePins = sharePins
    }

    /// `sharePins` is missing from settings saved before it was added.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stationaryThreshold = try container.decode(TimeInterval.self, forKey: .stationaryThreshold)
        sharePins = try container.decodeIfPresent(Bool.self, forKey: .sharePins) ?? true
    }

    static let `default` = AppSettings()
}
