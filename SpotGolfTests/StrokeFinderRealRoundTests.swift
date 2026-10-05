import XCTest
import CourseDataSwift
@testable import SpotGolf

/// Runs `StrokeFinder` on a real round exported from the app, to catch changes that make its
/// suggestions, or the imported hole starts, worse. The round lives in the git-ignored `Data` folder and the
/// course in the sibling CourseData checkout, so this is skipped wherever they are missing.
final class StrokeFinderRealRoundTests: XCTestCase {

    private static let projectDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Walnut Creek, 2026-09-25, imported the way the app imports it.
    private func walnutCreek() throws -> (round: Round, points: [TrackPoint], swings: [StrokeSuggestion]) {
        let roundURL = Self.projectDirectory.appendingPathComponent("Data/walnut-creek-2026-09-25.csv")
        let courseURL = Self.projectDirectory
            .appendingPathComponent("../CourseData/Data/US/CO/Westminster/Walnut-Creek-Golf-Preserve.json.gz")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: roundURL.path) &&
                          FileManager.default.fileExists(atPath: courseURL.path), "The real round is not on this machine")

        let course = try JSONDecoder().decode(Course.self, from: Data(contentsOf: courseURL).gzipDecompressed())
        let selection = CourseSelection(course: course, selectedSubCourseIndices: Array(course.subCourses.indices))
        let export = try TrackImporter.read(String(contentsOf: roundURL, encoding: .utf8))
        let (round, _) = try TrackImporter.round(from: export, courseSelection: selection)
        return (round, export.points, export.swings)
    }

    func testEveryHoleStartsFromThePath() throws {
        let (round, _, _) = try walnutCreek()

        XCTAssertEqual(round.holeTimeline.map(\.holeIndex), Array(0..<18))
        // The player's last fix within 10 m of green 1 was at 14:23:28, then they walked to tee 2
        let holeTwo = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-25T14:23:20Z"))
        XCTAssertEqual(round.holeTimeline[1].startedAt.timeIntervalSince(holeTwo), 10, accuracy: 10)
    }

    func testNoHoleOneSuggestionIsAtHoleTwosTee() throws {
        let (round, points, swings) = try walnutCreek()
        let teeTwo = HoleShape(hole: round.courseHole(at: 1), course: round.course)

        let holeOne = StrokeFinder.suggestions(in: round, holeIndex: 0, points: points, swings: swings, minStop: 30)

        for suggestion in holeOne {
            let spot = Coordinate(latitude: suggestion.latitude ?? 0, longitude: suggestion.longitude ?? 0)
            XCTAssertGreaterThan(teeTwo.metersToTee(spot) ?? 0, 20, "\(suggestion.timestamp) is at hole 2's tee")
        }
    }

    /// Swing and stop suggestions per hole when the rules were last tuned on this round. The
    /// scorecard had 4 4 5 3 3 3 2 4 4 4 3 2 4 1 4 3 3 3 full swings, plus putts.
    func testSuggestionsPerHole() throws {
        let (round, points, swings) = try walnutCreek()

        let found = (0..<18).map { hole in
            StrokeFinder.suggestions(in: round, holeIndex: hole, points: points, swings: swings, minStop: 30)
        }

        XCTAssertEqual(found.map { $0.filter(\.isSwing).count }, Self.swingsPerHole)
        XCTAssertEqual(found.map { $0.filter { !$0.isSwing }.count }, Self.stopsPerHole)
    }

    private static let swingsPerHole = [6, 6, 7, 3, 3, 3, 1, 5, 5, 4, 3, 2, 4, 1, 3, 3, 3, 3]
    private static let stopsPerHole = [1, 1, 1, 1, 1, 1, 2, 2, 1, 1, 1, 3, 5, 1, 1, 1, 1, 2]
}
