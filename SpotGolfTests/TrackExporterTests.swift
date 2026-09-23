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

    private func mark(offset: TimeInterval, type: BallMarkType = .regular) -> BallMark {
        BallMark(coordinate: CLLocationCoordinate2D(latitude: 39.9555, longitude: -105.0422),
                 timestamp: start.addingTimeInterval(offset), type: type)
    }

    func testHeaderAndTrackRowFormat() {
        let csv = TrackExporter.csv(round: Round(date: start),
                                    phone: [point(offset: 0, altitude: 1609.5, accuracy: 4.2)],
                                    watch: [])
        let lines = csv.split(separator: "\n")

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], "type,timestamp,latitude,longitude,altitude,horizontalAccuracy,source,hole,stroke,markType")
        XCTAssertEqual(lines[1], "track,2023-11-14T22:13:20.000Z,39.9555,-105.0422,1609.5,4.2,phone,,,")
    }

    func testMarkRowsCarryHoleStrokeAndType() {
        var round = Round(date: start)
        round.addMark(mark(offset: 10), toHoleIndex: 0)
        round.addMark(mark(offset: 20), toHoleIndex: 0)
        round.addMark(mark(offset: 30, type: .penalty), toHoleIndex: 1)

        let csv = TrackExporter.csv(round: round, phone: [], watch: [])
        let lines = csv.split(separator: "\n")

        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[1], "mark,2023-11-14T22:13:30.000Z,39.9555,-105.0422,,,,1,1,regular")
        XCTAssertEqual(lines[2], "mark,2023-11-14T22:13:40.000Z,39.9555,-105.0422,,,,1,2,regular")
        XCTAssertEqual(lines[3], "mark,2023-11-14T22:13:50.000Z,39.9555,-105.0422,,,,2,1,penalty")
    }

    func testTrackAndMarkRowsInterleaveInTimeOrder() {
        var round = Round(date: start)
        round.addMark(mark(offset: 15), toHoleIndex: 0)

        let csv = TrackExporter.csv(round: round,
                                    phone: [point(offset: 10)],
                                    watch: [point(offset: 20)])
        let types = csv.split(separator: "\n").dropFirst().map { $0.split(separator: ",")[0] }

        XCTAssertEqual(types, ["track", "mark", "track"])
    }

    func testMergesSourcesInTimeOrder() {
        let csv = TrackExporter.csv(round: Round(date: start),
                                    phone: [point(offset: 10), point(offset: 30)],
                                    watch: [point(offset: 20)])
        let sources = csv.split(separator: "\n").dropFirst()
            .map { $0.split(separator: ",", omittingEmptySubsequences: false)[6] }

        XCTAssertEqual(sources, ["phone", "watch", "phone"])
    }

    func testMissingAltitudeAndAccuracyAreBlank() {
        let csv = TrackExporter.csv(round: Round(date: start), phone: [], watch: [point(offset: 0)])
        let fields = csv.split(separator: "\n")[1].split(separator: ",", omittingEmptySubsequences: false)

        XCTAssertEqual(fields.count, 10)
        XCTAssertEqual(fields[4], "")
        XCTAssertEqual(fields[5], "")
        XCTAssertEqual(fields[6], "watch")
    }

    func testEmptyRoundProducesOnlyHeader() {
        let csv = TrackExporter.csv(round: Round(date: start), phone: [], watch: [])
        XCTAssertEqual(csv, TrackExporter.header + "\n")
    }

    func testFileName() {
        let round = Round(date: start)
        XCTAssertEqual(TrackExporter.fileName(for: round), "SpotGolf 2023-11-14.csv")
    }
}
