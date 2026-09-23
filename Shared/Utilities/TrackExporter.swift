import Foundation

/// Builds CSV exports of a round's GPS track and marks.
enum TrackExporter {
    static let header = "type,timestamp,latitude,longitude,altitude,horizontalAccuracy,source,hole,stroke,markType"

    /// One row per GPS fix and one per mark, all in time order.
    /// Track rows fill altitude/accuracy/source and leave the mark columns blank;
    /// mark rows fill hole (1-based), stroke (1-based) and mark type. Altitude and
    /// accuracy are blank when the fix had no valid reading.
    static func csv(round: Round, phone: [TrackPoint], watch: [TrackPoint]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var rows: [(timestamp: Date, line: String)] = []

        for (points, source) in [(phone, TrackSource.phone), (watch, TrackSource.watch)] {
            for point in points {
                let altitude = point.altitude.map { String($0) } ?? ""
                let accuracy = point.horizontalAccuracy.map { String($0) } ?? ""
                rows.append((point.timestamp,
                             "track,\(formatter.string(from: point.timestamp)),\(point.latitude),\(point.longitude),\(altitude),\(accuracy),\(source.rawValue),,,"))
            }
        }

        for (holeIndex, hole) in round.holes.enumerated() {
            for (markIndex, mark) in hole.marks.enumerated() {
                rows.append((mark.timestamp,
                             "mark,\(formatter.string(from: mark.timestamp)),\(mark.coordinate.latitude),\(mark.coordinate.longitude),,,,\(holeIndex + 1),\(markIndex + 1),\(mark.type.rawValue)"))
            }
        }

        let lines = rows.sorted { $0.timestamp < $1.timestamp }.map(\.line)
        return ([header] + lines).joined(separator: "\n") + "\n"
    }

    /// A file name like "SpotGolf 2026-03-15.csv" for the exported round.
    static func fileName(for round: Round) -> String {
        let date = round.date.formatted(.iso8601.year().month().day())
        return "SpotGolf \(date).csv"
    }
}
