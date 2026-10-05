import XCTest
import CourseDataSwift
@testable import SpotGolf

/// Imports a real round exported from the app. The round lives in the git-ignored `Data` folder
/// and the course in the sibling CourseData checkout, so this is skipped wherever they are missing.
final class TrackImporterRealRoundTests: XCTestCase {

    private static let projectDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Coal Creek, 2026-10-02. The walk from the 8th green to the 9th tee crossed the 18th tee.
    func testCoalCreekPlaysEveryHoleInOrder() throws {
        let roundURL = Self.projectDirectory.appendingPathComponent("Data/coal-creek-2026-10-02.csv")
        let courseURL = Self.projectDirectory
            .appendingPathComponent("../CourseData/Data/US/CO/Louisville/Coal-Creek-Golf-Course.json.gz")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: roundURL.path) &&
                          FileManager.default.fileExists(atPath: courseURL.path), "The real round is not on this machine")

        let course = try JSONDecoder().decode(Course.self, from: Data(contentsOf: courseURL).gzipDecompressed())
        let selection = CourseSelection(course: course, selectedSubCourseIndices: Array(course.subCourses.indices))
        let export = try TrackImporter.read(String(contentsOf: roundURL, encoding: .utf8))
        let (round, _) = try TrackImporter.round(from: export, courseSelection: selection)

        XCTAssertEqual(round.holeTimeline.map(\.holeIndex), Array(0..<18))
        // The player's last fix on the 17th green was at 18:16:24, and they reached the 18th tee at 18:17:40
        let formatter = ISO8601DateFormatter()
        let leftSeventeenthGreen = try XCTUnwrap(formatter.date(from: "2026-10-02T18:16:24Z"))
        let reachedEighteenthTee = try XCTUnwrap(formatter.date(from: "2026-10-02T18:17:40Z"))
        XCTAssertGreaterThan(round.holeTimeline[17].startedAt, leftSeventeenthGreen)
        XCTAssertLessThan(round.holeTimeline[17].startedAt, reachedEighteenthTee)
    }
}
