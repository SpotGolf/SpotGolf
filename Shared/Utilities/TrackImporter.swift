import Foundation
import CoreLocation

/// Reads a `TrackExporter` CSV back into a round, so a recorded round can be replayed on
/// another device, such as the simulator.
enum TrackImporter {
    struct Export {
        var points: [TrackPoint] = []
        var swings: [StrokeSuggestion] = []
        /// Strokes, with the 1-based hole they are on, in stroke order.
        var strokes: [(stroke: Stroke, hole: Int)] = []
    }

    enum ImportError: LocalizedError {
        case wrongHeader
        case empty

        var errorDescription: String? {
            switch self {
            case .wrongHeader: "The file is not a SpotGolf round export."
            case .empty: "The file has no GPS fixes."
            }
        }
    }

    /// The fixes, swings and strokes in a CSV. Rows that can't be read are skipped. The hole on
    /// swing rows is ignored: `StrokeFinder` works out the hole starts again.
    static func read(_ csv: String) throws -> Export {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lines = csv.split(whereSeparator: \.isNewline)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == TrackExporter.header else { throw ImportError.wrongHeader }

        var export = Export()
        var strokes: [(stroke: Stroke, hole: Int, number: Int)] = []
        // type,timestamp,latitude,longitude,altitude,horizontalAccuracy,source,hole,stroke,strokeType,peakG
        for line in lines.dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 11 else { continue }
            switch fields[0] {
            case "track":
                guard let date = formatter.date(from: fields[1]),
                      let lat = Double(fields[2]), let lon = Double(fields[3]) else { continue }
                export.points.append(TrackPoint(timestamp: date, latitude: lat, longitude: lon, altitude: Double(fields[4]),
                                                horizontalAccuracy: Double(fields[5])))
            case "swing":
                guard let date = formatter.date(from: fields[1]), let peakG = Float(fields[10]) else { continue }
                export.swings.append(.swing(at: date, peakG: peakG))
            case "stroke":
                guard let lat = Double(fields[2]), let lon = Double(fields[3]),
                      let hole = Int(fields[7]), let number = Int(fields[8]) else { continue }
                let type = StrokeType(rawValue: fields[9]) ?? .regular
                strokes.append((Stroke(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), type: type), hole, number))
            default:
                continue
            }
        }
        export.strokes = strokes.sorted { ($0.hole, $0.number) < ($1.hole, $1.number) }.map { ($0.stroke, $0.hole) }
        return export
    }

    /// An active round on `courseSelection` holding the export's strokes, and its stream records.
    /// It stays active so it can still be changed. The timeline holds only the round start:
    /// `PhoneSync.importRound` works out the rest from the GPS.
    static func round(from export: Export, courseSelection: CourseSelection,
                      id: UUID = UUID()) throws -> (round: Round, records: [StreamRecord]) {
        guard let start = export.points.first?.timestamp else { throw ImportError.empty }
        var round = Round(id: id, date: start, courseSelection: courseSelection)
        for (stroke, hole) in export.strokes {
            round.addStroke(stroke, toHoleIndex: hole - 1)
        }

        let records = (export.points.map(StreamRecord.fix) + export.swings.map(StreamRecord.swing))
            .sorted { $0.timestamp < $1.timestamp }
        return (round, records)
    }
}
