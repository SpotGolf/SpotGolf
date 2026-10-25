import CoreLocation
import CourseDataSwift
import XCTest
@testable import SpotGolf

final class RoundArchiveTests: XCTestCase {

    /// An ended round with strokes, a pin, hole starts and a moved display hole.
    static func endedRound(id: UUID = UUID(), date: Date = Date(timeIntervalSince1970: 1_760_280_000)) -> Round {
        let round = Round(id: id, date: date, courseSelection: .test)
        let tee = CLLocationCoordinate2D(latitude: 39.0, longitude: -105.0)
        round.holes = [
            RoundHole(strokes: [Stroke(coordinate: tee, origin: .manual, hitAt: date.addingTimeInterval(60)),
                                Stroke(coordinate: CLLocationCoordinate2D(latitude: 39.001, longitude: -105.0),
                                       penaltyStrokes: 1, quality: .bad, club: Club.named("7i"))]),
            RoundHole(strokes: [Stroke(coordinate: tee)])
        ]
        round.holeStarts[1] = date.addingTimeInterval(900)
        round.pins[0] = PinLocation(coordinate: CLLocationCoordinate2D(latitude: 39.002, longitude: -105.0),
                                    setAt: date.addingTimeInterval(300))
        round.displayHole = DisplayHole(holeIndex: 1, changedAt: date.addingTimeInterval(900))
        round.status = .ended
        round.endedAt = date.addingTimeInterval(3_600)
        round.endConfirmed = true
        round.changedAt = date.addingTimeInterval(4_000)
        round.updateStats()
        return round
    }

    static func records(count: Int, from date: Date = Date(timeIntervalSince1970: 1_760_280_000)) -> Data {
        StreamRecord.data(for: (0..<count).map { index in
            index % 10 == 9
                ? .swing(StrokeSuggestion(timestamp: date.addingTimeInterval(Double(index)), kind: .swing(peakG: 12)))
                : .fix(TrackPoint(timestamp: date.addingTimeInterval(Double(index)), latitude: 39 + Double(index) * 1e-6,
                                  longitude: -105, altitude: 1_600, horizontalAccuracy: 5))
        })
    }

    func testARoundComesBackTheSame() throws {
        let round = Self.endedRound()
        let records = Self.records(count: 500)

        let archive = try RoundArchive.read(gzipped: RoundArchive(round: round, records: records).gzipped())
        let copy = archive.makeRound()

        XCTAssertEqual(copy.id, round.id)
        XCTAssertEqual(copy.date, round.date)
        XCTAssertEqual(copy.status, .ended)
        XCTAssertTrue(copy.endConfirmed)
        XCTAssertEqual(copy.endedAt, round.endedAt)
        XCTAssertEqual(copy.changedAt, round.changedAt)
        XCTAssertEqual(copy.holes, round.holes)
        XCTAssertEqual(copy.holeStarts, round.holeStarts)
        XCTAssertEqual(copy.pins, round.pins)
        XCTAssertEqual(copy.displayHole, round.displayHole)
        XCTAssertEqual(copy.courseSelection, round.courseSelection)
        XCTAssertEqual(try archive.records(), records)
    }

    func testOnlyTheNinesPlayedAreKept() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Broadlands-Golf-Course.json", withExtension: "gz"))
        let course = try JSONDecoder().decode(Course.self, from: Data(contentsOf: url).gzipDecompressed())
        XCTAssertGreaterThan(course.subCourses.count, 1)
        let round = Round(courseSelection: CourseSelection(course: course, selectedSubCourseIndices: [1]))

        let copy = try RoundArchive.read(gzipped: RoundArchive(round: round, records: Data()).gzipped()).makeRound()

        XCTAssertEqual(copy.courseSelection.course.subCourses.map(\.name), [course.subCourses[1].name])
        XCTAssertLessThan(copy.courseSelection.course.features.count, course.features.count)
        XCTAssertEqual(copy.courseSelection.orderedHoles.map(\.number), round.courseSelection.orderedHoles.map(\.number))
    }

    func testApplyingMakesAnExistingRoundMatch() throws {
        let round = Self.endedRound()
        let archive = RoundArchive(round: round, records: Data())
        let other = Round(id: round.id, date: round.date, status: .ended, courseSelection: .test)

        archive.apply(to: other)

        XCTAssertEqual(other.holes, round.holes)
        XCTAssertEqual(other.pins, round.pins)
        XCTAssertEqual(other.changedAt, round.changedAt)
    }

    func testANewerVersionIsRefused() throws {
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(RoundArchive(round: Self.endedRound(), records: Data()))) as? [String: Any] ?? [:]
        json["version"] = RoundArchive.currentVersion + 1
        json["somethingNew"] = true
        let gzipped = try JSONSerialization.data(withJSONObject: json).gzipCompressed()

        XCTAssertThrowsError(try RoundArchive.read(gzipped: gzipped)) { error in
            XCTAssertEqual(error as? RoundArchive.ArchiveError, .newerVersion(RoundArchive.currentVersion + 1))
        }
    }
}
