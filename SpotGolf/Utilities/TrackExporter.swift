import Foundation

/// Builds CSV exports of a round's GPS track, swings, and strokes.
enum TrackExporter {
    static let header = "type,timestamp,latitude,longitude,altitude,horizontalAccuracy,source,hole,stroke,strokeType,peakG"

    /// One row per GPS fix and swing in time order, then one row per stroke in hole and stroke
    /// order. Strokes have no time, so their timestamp is blank. Track rows fill altitude/accuracy/source and leave the rest blank. Swing rows fill the
    /// location of the nearest fix (blank if none is close enough), source, hole (1-based, from
    /// the hole timeline), and peak force in g. Stroke rows fill hole (1-based), stroke (1-based)
    /// and stroke type. Altitude and accuracy are blank when the fix had no valid reading.
    static func csv(round: Round, points: [TrackPoint], swings: [StrokeSuggestion]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var rows: [(timestamp: Date, line: String)] = []

        for point in points {
            let altitude = point.altitude.map { String($0) } ?? ""
            let accuracy = point.horizontalAccuracy.map { String($0) } ?? ""
            rows.append((point.timestamp,
                         "track,\(formatter.string(from: point.timestamp)),\(point.latitude),\(point.longitude),\(altitude),\(accuracy),watch,,,,"))
        }

        for swing in swings {
            let fix = StrokeFinder.nearestFix(to: swing.timestamp, in: points)
            let latitude = fix.map { String($0.latitude) } ?? ""
            let longitude = fix.map { String($0.longitude) } ?? ""
            let hole = round.holeIndex(at: swing.timestamp) + 1
            rows.append((swing.timestamp,
                         "swing,\(formatter.string(from: swing.timestamp)),\(latitude),\(longitude),,,watch,\(hole),,,\(swing.peakG ?? 0)"))
        }

        var lines = rows.sorted { $0.timestamp < $1.timestamp }.map(\.line)
        for (holeIndex, hole) in round.holes.enumerated() {
            for (strokeIndex, stroke) in hole.strokes.enumerated() {
                lines.append("stroke,,\(stroke.coordinate.latitude),\(stroke.coordinate.longitude),,,,\(holeIndex + 1),\(strokeIndex + 1),\(stroke.type.rawValue),")
            }
        }
        return ([header] + lines).joined(separator: "\n") + "\n"
    }

    /// A file name like "SpotGolf 2026-03-15.csv" for the exported round.
    static func fileName(for round: Round) -> String {
        let date = round.date.formatted(.iso8601.year().month().day())
        return "SpotGolf \(date).csv"
    }
}
