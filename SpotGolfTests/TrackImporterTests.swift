import XCTest
import CoreLocation
@testable import SpotGolf

final class TrackImporterTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func point(offset: TimeInterval) -> TrackPoint {
        TrackPoint(timestamp: start.addingTimeInterval(offset), latitude: 39.9555 + offset / 100_000, longitude: -105.0422,
                   altitude: 1609.5, horizontalAccuracy: 4.2)
    }

    private var swings: [StrokeSuggestion] {
        [.swing(at: start.addingTimeInterval(20), peakG: 11.5), .swing(at: start.addingTimeInterval(120), peakG: 14)]
    }

    /// A round on two holes: fixes every 10 seconds, a swing and a stroke on each hole.
    private func exportedCSV() -> String {
        var round = Round(date: start, courseSelection: .test)
        round.startHole(1, at: start.addingTimeInterval(100), source: .autoAdvance)
        round.addStroke(Stroke(coordinate: CLLocationCoordinate2D(latitude: 39.9, longitude: -105.0)), toHoleIndex: 0)
        round.addStroke(Stroke(coordinate: CLLocationCoordinate2D(latitude: 39.8, longitude: -105.1), type: .penalty),
                        toHoleIndex: 1)
        let points = stride(from: 0.0, through: 200, by: 10).map(point)
        return TrackExporter.csv(round: round, points: points, swings: swings)
    }

    func testReadsWhatTheExporterWrites() throws {
        let export = try TrackImporter.read(exportedCSV())

        XCTAssertEqual(export.points, stride(from: 0.0, through: 200, by: 10).map(point))
        XCTAssertEqual(export.swings, swings)
        XCTAssertEqual(export.strokes.map(\.hole), [1, 2])
        XCTAssertEqual(export.strokes.map(\.stroke.type), [.regular, .penalty])
        XCTAssertEqual(export.strokes.map(\.stroke.latitude), [39.9, 39.8])
    }

    func testRejectsAFileThatIsNotAnExport() {
        XCTAssertThrowsError(try TrackImporter.read("a,b,c\n1,2,3\n"))
    }

    func testRejectsTheOldHeader() {
        let old = "type,timestamp,latitude,longitude,altitude,horizontalAccuracy,source,hole,stroke,markType,peakG\n"
        XCTAssertThrowsError(try TrackImporter.read(old))
    }

    func testBuildsAnActiveRoundWithOnlyTheRoundStart() throws {
        let export = try TrackImporter.read(exportedCSV())
        let (round, records) = try TrackImporter.round(from: export, courseSelection: .test)

        XCTAssertEqual(round.status, .active)
        XCTAssertEqual(round.date, start)
        XCTAssertNil(round.endedAt)
        XCTAssertEqual(round.holeTimeline.map(\.holeIndex), [0])
        XCTAssertEqual(round.holes.map { $0.strokes.count }, [1, 1])

        XCTAssertEqual(records.count, 23)
        XCTAssertEqual(records.map(\.timestamp), records.map(\.timestamp).sorted())
        XCTAssertEqual(records.filter { if case .swing = $0 { true } else { false } }.count, 2)
    }

    func testRoundWithoutFixesIsAnError() throws {
        let export = try TrackImporter.read(TrackExporter.header + "\n")
        XCTAssertThrowsError(try TrackImporter.round(from: export, courseSelection: .test))
    }
}
