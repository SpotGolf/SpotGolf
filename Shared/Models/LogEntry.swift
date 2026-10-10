import Foundation
import SwiftData

/// One line of the app's log, saved with SwiftData. `seq` is the line's position among the
/// lines of the same round and device, from 0; outside a round it keeps counting up as old
/// lines are trimmed. The watch's lines keep the watch's `seq` on the phone.
@Model
final class LogEntry {
    /// The round the line belongs to, or nil outside a round.
    var roundID: UUID?
    /// `LogDevice`.
    var device: String
    var seq: Int
    var timestamp: Date
    /// `LogLevel`.
    var level: String
    var category: String
    var message: String

    init(roundID: UUID?, device: LogDevice, seq: Int, line: LogLine) {
        self.roundID = roundID
        self.device = device.rawValue
        self.seq = seq
        timestamp = line.timestamp
        level = line.level.rawValue
        category = line.category
        message = line.message
    }

    var line: LogLine {
        LogLine(timestamp: timestamp,
                device: LogDevice(rawValue: device) ?? .phone,
                level: LogLevel(rawValue: level) ?? .notice,
                category: category, message: message)
    }
}
