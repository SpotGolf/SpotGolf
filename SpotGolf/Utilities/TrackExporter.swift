import Foundation

/// Builds CSV exports of a round's GPS track, swings, contacts, and strokes.
enum TrackExporter {
    static let header = "type,timestamp,latitude,longitude,altitude,horizontalAccuracy,source,hole,stroke,strokeType,peakG,score,burst,click,club,quality"
    /// Exports from before strokes recorded their shot quality, which the importer still reads.
    static let headerWithoutQuality = "type,timestamp,latitude,longitude,altitude,horizontalAccuracy,source,hole,stroke,strokeType,peakG,score,burst,click,club"
    /// Exports from before strokes recorded their club, which the importer still reads.
    static let headerWithoutClubs = "type,timestamp,latitude,longitude,altitude,horizontalAccuracy,source,hole,stroke,strokeType,peakG,score,burst,click"
    /// Exports from before the watch recorded contacts, which the importer still reads.
    static let headerWithoutContacts = "type,timestamp,latitude,longitude,altitude,horizontalAccuracy,source,hole,stroke,strokeType,peakG"

    /// One row per GPS fix, swing and contact in time order, then one row per stroke in hole and
    /// stroke order. Strokes have no time, so their timestamp is blank. Track rows fill
    /// altitude/accuracy/source and leave the rest blank. Swing rows fill the location of the
    /// nearest fix (blank if none is close enough), source, hole (its number in nine order, from
    /// the hole timeline), and peak force in g; contact rows the same with score, burst and click instead.
    /// Stroke rows fill hole (its number), stroke (1-based), the penalty strokes in strokeType, the
    /// club and the shot quality. Event rows fill
    /// source, hole, the event's name in strokeType and its value in peakG. Altitude and
    /// accuracy are blank when the fix had no valid reading.
    static func csv(round: Round, points: [TrackPoint], swings: [StrokeSuggestion], contacts: [ContactEvent] = [],
                    events: [StreamEvent] = []) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var rows: [(timestamp: Date, line: String)] = []

        for point in points {
            let altitude = point.altitude.map { String($0) } ?? ""
            let accuracy = point.horizontalAccuracy.map { String($0) } ?? ""
            rows.append((point.timestamp,
                         "track,\(formatter.string(from: point.timestamp)),\(point.latitude),\(point.longitude),\(altitude),\(accuracy),watch,,,,,,,,,"))
        }

        for swing in swings {
            let fix = StrokeFinder.nearestFix(to: swing.timestamp, in: points)
            let latitude = fix.map { String($0.latitude) } ?? ""
            let longitude = fix.map { String($0.longitude) } ?? ""
            let hole = round.holeNumber(at: round.holeIndex(at: swing.timestamp))
            rows.append((swing.timestamp,
                         "swing,\(formatter.string(from: swing.timestamp)),\(latitude),\(longitude),,,watch,\(hole),,,\(swing.peakG ?? 0),,,,,"))
        }

        for contact in contacts {
            let fix = StrokeFinder.nearestFix(to: contact.timestamp, in: points)
            let latitude = fix.map { String($0.latitude) } ?? ""
            let longitude = fix.map { String($0.longitude) } ?? ""
            let hole = round.holeNumber(at: round.holeIndex(at: contact.timestamp))
            rows.append((contact.timestamp,
                         "contact,\(formatter.string(from: contact.timestamp)),\(latitude),\(longitude),,,watch,\(hole),,,,\(contact.score),\(contact.burst),\(contact.click),,"))
        }

        // The watch's workout and sensor events: the code's name where a stroke's type goes, its value where a swing's peak goes
        for event in events {
            let hole = round.holeNumber(at: round.holeIndex(at: event.timestamp))
            rows.append((event.timestamp,
                         "event,\(formatter.string(from: event.timestamp)),,,,,watch,\(hole),,\(event.name),\(event.value),,,,,"))
        }

        var lines = rows.sorted { $0.timestamp < $1.timestamp }.map(\.line)
        for (holeIndex, hole) in round.holes.enumerated() {
            for (strokeIndex, stroke) in hole.strokes.enumerated() {
                lines.append("stroke,,\(stroke.coordinate.latitude),\(stroke.coordinate.longitude),,,,\(round.holeNumber(at: holeIndex)),\(strokeIndex + 1),\(stroke.penaltyStrokes),,,,,\(stroke.clubID ?? ""),\(stroke.quality.rawValue)")
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
