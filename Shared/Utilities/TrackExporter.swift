import Foundation

/// Builds CSV exports of a round's GPS track.
enum TrackExporter {
    /// One row per GPS fix from both devices, in time order.
    /// Columns: timestamp,latitude,longitude,altitude,source. Altitude is blank
    /// when the fix had no valid reading.
    static func csv(phone: [TrackPoint], watch: [TrackPoint]) -> String {
        let rows = (phone.map { ($0, TrackSource.phone) } + watch.map { ($0, TrackSource.watch) })
            .sorted { $0.0.timestamp < $1.0.timestamp }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines = ["timestamp,latitude,longitude,altitude,source"]
        for (point, source) in rows {
            let altitude = point.altitude.map { String($0) } ?? ""
            lines.append("\(formatter.string(from: point.timestamp)),\(point.latitude),\(point.longitude),\(altitude),\(source.rawValue)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A file name like "SpotGolf 2026-03-15.csv" for the exported round.
    static func fileName(for round: Round) -> String {
        let date = round.date.formatted(.iso8601.year().month().day())
        return "SpotGolf \(date).csv"
    }
}
