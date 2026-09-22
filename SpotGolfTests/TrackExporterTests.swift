import XCTest
@testable import SpotGolf

final class TrackExporterTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func point(offset: TimeInterval, lat: Double = 39.9555, lon: Double = -105.0422,
                       altitude: Double? = nil) -> TrackPoint {
        TrackPoint(timestamp: start.addingTimeInterval(offset), latitude: lat, longitude: lon, altitude: altitude)
    }

    func testHeaderAndRowFormat() throws {
        let csv = TrackExporter.csv(phone: [point(offset: 0, altitude: 1609.5)], watch: [])
        let lines = csv.split(separator: "\n")

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], "timestamp,latitude,longitude,altitude,source")
        XCTAssertEqual(lines[1], "2023-11-14T22:13:20.000Z,39.9555,-105.0422,1609.5,phone")
    }

    func testMergesSourcesInTimeOrder() {
        let csv = TrackExporter.csv(phone: [point(offset: 10), point(offset: 30)],
                                    watch: [point(offset: 20)])
        let sources = csv.split(separator: "\n").dropFirst().map { $0.split(separator: ",").last! }

        XCTAssertEqual(sources, ["phone", "watch", "phone"])
    }

    func testMissingAltitudeIsBlank() {
        let csv = TrackExporter.csv(phone: [], watch: [point(offset: 0, altitude: nil)])
        let fields = csv.split(separator: "\n")[1].split(separator: ",", omittingEmptySubsequences: false)

        XCTAssertEqual(fields.count, 5)
        XCTAssertEqual(fields[3], "")
        XCTAssertEqual(fields[4], "watch")
    }

    func testEmptyTracksProduceOnlyHeader() {
        let csv = TrackExporter.csv(phone: [], watch: [])
        XCTAssertEqual(csv, "timestamp,latitude,longitude,altitude,source\n")
    }

    func testFileName() {
        let round = Round(date: start)
        XCTAssertEqual(TrackExporter.fileName(for: round), "SpotGolf 2023-11-14.csv")
    }
}
