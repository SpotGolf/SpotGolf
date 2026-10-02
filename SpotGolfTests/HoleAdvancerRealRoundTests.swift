import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolf

/// Replays a real round through `HoleAdvancer`, the way the watch feeds it. The round lives in
/// the git-ignored `Data` folder and the course in the sibling CourseData checkout, so this is
/// skipped wherever they are missing.
final class HoleAdvancerRealRoundTests: XCTestCase {

    private static let projectDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Flatirons, 2026-10-01: the front nine, then the walk back toward the clubhouse.
    private func flatirons() throws -> (selection: CourseSelection, fixes: [CLLocation]) {
        let roundURL = Self.projectDirectory.appendingPathComponent("Data/flatirons-2026-10-01.csv")
        let courseURL = Self.projectDirectory
            .appendingPathComponent("../CourseData/Data/US/CO/Boulder/Flatirons-Golf-Course.json.gz")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: roundURL.path) &&
                          FileManager.default.fileExists(atPath: courseURL.path), "The real round is not on this machine")

        let course = try JSONDecoder().decode(Course.self, from: Data(contentsOf: courseURL).gzipDecompressed())
        let selection = CourseSelection(course: course, selectedSubCourseIndices: Array(course.subCourses.indices))
        let export = try TrackImporter.read(String(contentsOf: roundURL, encoding: .utf8))
        let fixes = export.points.map { point in
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                       altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: point.timestamp)
        }
        return (selection, fixes)
    }

    /// Each hole changes after the player's last fix on the green and no later than reaching
    /// the next tee, and the walk in after the 9th never starts the 10th.
    func testHolesChangeAfterLeavingTheGreenAndByTheTee() throws {
        let (selection, fixes) = try flatirons()
        let holes = selection.orderedHoles
        var advancer = HoleAdvancer()
        var holeIndex = 0
        var holeStart = 0
        var advances = 0

        for (index, location) in fixes.enumerated() {
            guard let next = advancer.advance(location: location, courseSelection: selection, currentHoleIndex: holeIndex) else { continue }
            let green = StrokeFinder.HoleShape(hole: holes[holeIndex], course: selection.course)
            let tees = StrokeFinder.HoleShape(hole: holes[next], course: selection.course)
            let reachedTee = fixes[holeStart...].firstIndex { tees.metersToTee(Self.coordinate($0)) == 0 } ?? fixes.endIndex
            // The player's real exit: the last fix at the green before walking onto the next tee
            let lastOnGreen = try XCTUnwrap(fixes[holeStart..<reachedTee].lastIndex { green.metersToGreen(Self.coordinate($0)).map { $0 <= 5 } ?? false },
                                            "Hole \(holeIndex + 1) changed before the player reached its green")

            XCTAssertGreaterThan(index, lastOnGreen, "Hole \(holeIndex + 1) changed before the player left its green")
            XCTAssertLessThanOrEqual(index, reachedTee, "Hole \(next + 1) started after its tee was reached")
            holeIndex = next
            holeStart = index
            advances += 1
        }

        XCTAssertEqual(holeIndex, 8, "The round should end on the 9th")
        XCTAssertEqual(advances, 8)
    }

    private static func coordinate(_ location: CLLocation) -> Coordinate {
        Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
}
