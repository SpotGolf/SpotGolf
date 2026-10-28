import Foundation

/// A piece of the watch's log, sent to the phone as a file with `transferFile`, the way Putt
/// Data Sharing sends sessions. See plans/2026-10-28-unified-log.md.
enum LogChunk {
    enum FileKey {
        /// The chunk's file name, which the phone uses to skip a chunk it already has.
        static let chunk = "logChunk"
    }

    /// `20261009-161233-<uuid>.log`, so names sort in the order the chunks were made.
    static func fileName(at date: Date) -> String {
        "\(date.formatted(nameFormat))-\(UUID().uuidString).\(LogFile.fileExtension)"
    }

    private static let nameFormat = Date.VerbatimFormatStyle(
        format: "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
        timeZone: .gmt, calendar: Calendar(identifier: .gregorian))
}
