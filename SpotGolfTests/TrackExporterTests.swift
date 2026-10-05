import XCTest
import CoreLocation
@testable import SpotGolf

final class TrackExporterTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func point(offset: TimeInterval, lat: Double = 39.9555, lon: Double = -105.0422,
                       altitude: Double? = nil, accuracy: Double? = nil) -> TrackPoint {
        TrackPoint(timestamp: start.addingTimeInterval(offset), latitude: lat, longitude: lon,
                   altitude: altitude, horizontalAccuracy: accuracy)
    }

    private func stroke(type: StrokeType = .regular) -> Stroke {
        Stroke(coordinate: CLLocationCoordinate2D(latitude: 39.9555, longitude: -105.0422), type: type)
    }

    func testHeaderAndTrackRowFormat() {
        let csv = TrackExporter.csv(round: Round(date: start, courseSelection: .test),
                                    points: [point(offset: 0, altitude: 1609.5, accuracy: 4.2)],
                                    swings: [])
        let lines = csv.split(separator: "\n")

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], "type,timestamp,latitude,longitude,altitude,horizontalAccuracy,source,hole,stroke,strokeType,peakG")
        XCTAssertEqual(lines[1], "track,2023-11-14T22:13:20.000Z,39.9555,-105.0422,1609.5,4.2,watch,,,,")
    }

    func testStrokeRowsCarryHoleStrokeAndType() {
        var round = Round(date: start, courseSelection: .test)
        round.addStroke(stroke(), toHoleIndex: 0)
        round.addStroke(stroke(), toHoleIndex: 0)
        round.addStroke(stroke(type: .penalty), toHoleIndex: 1)

        let csv = TrackExporter.csv(round: round, points: [], swings: [])
        let lines = csv.split(separator: "\n")

        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[1], "stroke,,39.9555,-105.0422,,,,1,1,regular,")
        XCTAssertEqual(lines[2], "stroke,,39.9555,-105.0422,,,,1,2,regular,")
        XCTAssertEqual(lines[3], "stroke,,39.9555,-105.0422,,,,2,1,penalty,")
    }

    func testSwingRowCarriesNearestFixHoleAndPeak() {
        var round = Round(date: start, courseSelection: .test)
        round.startHole(1, at: start.addingTimeInterval(20), source: .stroke)
        let swing = StrokeSuggestion.swing(at: start.addingTimeInterval(32), peakG: 12.5)

        let csv = TrackExporter.csv(round: round,
                                    points: [point(offset: 30, lat: 39.1, lon: -105.1), point(offset: 40, lat: 39.2, lon: -105.2)],
                                    swings: [swing])
        let lines = csv.split(separator: "\n")

        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[2], "swing,2023-11-14T22:13:52.000Z,39.1,-105.1,,,watch,2,,,12.5")
    }

    func testSwingRowWithoutNearbyFixHasBlankLocation() {
        let round = Round(date: start, courseSelection: .test)
        let swing = StrokeSuggestion.swing(at: start.addingTimeInterval(60), peakG: 11)

        let csv = TrackExporter.csv(round: round, points: [point(offset: 0)], swings: [swing])
        let fields = csv.split(separator: "\n")[2].split(separator: ",", omittingEmptySubsequences: false)

        XCTAssertEqual(fields[0], "swing")
        XCTAssertEqual(fields[2], "")
        XCTAssertEqual(fields[3], "")
        XCTAssertEqual(fields[7], "1")
        XCTAssertEqual(fields[10], "11.0")
    }

    func testTimedRowsInterleaveAndStrokesComeLast() {
        var round = Round(date: start, courseSelection: .test)
        round.addStroke(stroke(), toHoleIndex: 0)

        let csv = TrackExporter.csv(round: round,
                                    points: [point(offset: 10), point(offset: 20)],
                                    swings: [StrokeSuggestion.swing(at: start.addingTimeInterval(12), peakG: 10)])
        let types = csv.split(separator: "\n").dropFirst().map { $0.split(separator: ",")[0] }

        XCTAssertEqual(types, ["track", "swing", "track", "stroke"])
    }

    func testMissingAltitudeAndAccuracyAreBlank() {
        let csv = TrackExporter.csv(round: Round(date: start, courseSelection: .test), points: [point(offset: 0)], swings: [])
        let fields = csv.split(separator: "\n")[1].split(separator: ",", omittingEmptySubsequences: false)

        XCTAssertEqual(fields.count, 11)
        XCTAssertEqual(fields[4], "")
        XCTAssertEqual(fields[5], "")
        XCTAssertEqual(fields[6], "watch")
    }

    func testEmptyRoundProducesOnlyHeader() {
        let csv = TrackExporter.csv(round: Round(date: start, courseSelection: .test), points: [], swings: [])
        XCTAssertEqual(csv, TrackExporter.header + "\n")
    }

    func testFileName() {
        let round = Round(date: start, courseSelection: .test)
        XCTAssertEqual(TrackExporter.fileName(for: round), "SpotGolf 2023-11-14.csv")
    }
}
