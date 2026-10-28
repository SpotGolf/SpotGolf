import CourseDataSwift
import Foundation

/// "Share logs…": every log file, oldest first, gzipped into one file to send to support.
enum LogShare {
    /// Writes `SpotGolf-log-<yyyy-MM-dd-HHmm>.log.gz` into `directory` and returns it.
    static func gzip(_ file: LogFile, into directory: URL = FileManager.default.temporaryDirectory,
                     now: Date = Date()) throws -> URL {
        let url = directory.appendingPathComponent("SpotGolf-log-\(now.formatted(nameFormat)).log.gz")
        try file.allData().gzipCompressed().write(to: url, options: .atomic)
        return url
    }

    private static let nameFormat = Date.VerbatimFormatStyle(
        format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)",
        timeZone: .current, calendar: Calendar(identifier: .gregorian))
}
