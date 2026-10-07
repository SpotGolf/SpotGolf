import Foundation
import CoreLocation
import CourseDataSwift

/// Reads a `TrackExporter` CSV back into a round, so a recorded round can be replayed on
/// another device, such as the simulator.
enum TrackImporter {
    /// A fix this close to a tee counts as reaching it: the tee box and GPS drift.
    static let teeArrivalRadius: CLLocationDistance = 10
    /// A fix on the green or this close to its edge counts as at the green: GPS drift and the fringe.
    static let greenEdgeMargin: CLLocationDistance = 10

    struct Export {
        var points: [TrackPoint] = []
        var swings: [StrokeSuggestion] = []
        var contacts: [ContactEvent] = []
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

    /// The fixes, swings, contacts and strokes in a CSV. Rows that can't be read are skipped.
    /// The hole on swing and contact rows is ignored: the hole starts are worked out again from
    /// the GPS. Exports from before contacts were recorded are read too.
    static func read(_ csv: String) throws -> Export {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lines = csv.split(whereSeparator: \.isNewline)
        let header = lines.first?.trimmingCharacters(in: .whitespaces)
        guard header == TrackExporter.header || header == TrackExporter.headerWithoutContacts else { throw ImportError.wrongHeader }

        var export = Export()
        var strokes: [(stroke: Stroke, hole: Int, number: Int)] = []
        // type,timestamp,latitude,longitude,altitude,horizontalAccuracy,source,hole,stroke,strokeType,peakG,score,burst,click
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
            case "contact":
                guard fields.count >= 14, let date = formatter.date(from: fields[1]), let score = Float(fields[11]),
                      let burst = Float(fields[12]), let click = Float(fields[13]) else { continue }
                export.contacts.append(ContactEvent(timestamp: date, score: score, burst: burst, click: click, turning: 0))
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
    /// It stays active so it can still be changed. The timeline comes from the GPS and the course.
    static func round(from export: Export, courseSelection: CourseSelection,
                      id: UUID = UUID()) throws -> (round: Round, records: [StreamRecord]) {
        guard let start = export.points.first?.timestamp else { throw ImportError.empty }
        var round = Round(id: id, date: start, courseSelection: courseSelection)
        round.holeTimeline = holeTimeline(of: round, points: export.points)
        for (stroke, hole) in export.strokes {
            round.addStroke(stroke, toHoleIndex: hole - 1)
        }

        let records = (export.points.map(StreamRecord.fix) + export.swings.map(StreamRecord.swing)
                       + export.contacts.map(StreamRecord.contact))
            .sorted { $0.timestamp < $1.timestamp }
        return (round, records)
    }

    // MARK: - Hole timeline

    /// The round's hole timeline from the GPS path and the course alone. Holes are taken in
    /// playing order, each after the one before it. A hole starts just after the player last
    /// left the previous green before reaching its tee, or on reaching its tee when they were
    /// never at that green but were at the previous tee. A hole whose tee was never reached
    /// that way is left out.
    static func holeTimeline(of round: Round, points: [TrackPoint]) -> [HoleStart] {
        var timeline = [HoleStart(holeIndex: 0, startedAt: round.date, source: .roundStart)]
        guard round.lastHoleIndex > 0 else { return timeline }
        for hole in 1...round.lastHoleIndex {
            guard let start = start(of: hole, in: round, after: timeline[timeline.count - 1].startedAt, points: points) else { continue }
            timeline.append(HoleStart(holeIndex: hole, startedAt: start, source: .estimated))
        }
        return timeline
    }

    /// When `hole` started, after `after`, or nil when its tee was not reached.
    private static func start(of hole: Int, in round: Round, after: Date, points: [TrackPoint]) -> Date? {
        let tee = HoleShape(hole: round.courseHole(at: hole), course: round.course)
        guard !tee.tees.isEmpty else { return nil }
        let previous = HoleShape(hole: round.courseHole(at: hole - 1), course: round.course)
        let window = points.filter { $0.timestamp > after }

        func isAtPreviousGreen(_ point: TrackPoint) -> Bool {
            previous.metersToGreen(Coordinate(latitude: point.latitude, longitude: point.longitude)).map { $0 <= greenEdgeMargin } ?? false
        }
        func isAt(_ tees: HoleShape, _ point: TrackPoint) -> Bool {
            tees.metersToTee(Coordinate(latitude: point.latitude, longitude: point.longitude)).map { $0 <= teeArrivalRadius } ?? false
        }

        // The tee only counts once the player has been at the previous green, or at the previous
        // tee when they never reached that green, so a tee passed on the way there does not
        guard let from = (window.first(where: isAtPreviousGreen) ?? window.first { isAt(previous, $0) })?.timestamp,
              let arrival = window.first(where: { $0.timestamp >= from && isAt(tee, $0) })?.timestamp else { return nil }
        guard let lastAtGreen = window.last(where: { $0.timestamp < arrival && isAtPreviousGreen($0) }) else { return arrival }
        return window.first { $0.timestamp > lastAtGreen.timestamp }?.timestamp ?? arrival
    }
}
