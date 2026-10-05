import XCTest
import CourseDataSwift
@testable import SpotGolf

/// Runs `StrokeFinder` on real rounds exported from the app, to catch changes that make its
/// suggestions, or the imported hole starts, worse. The rounds live in the git-ignored `Data`
/// folder and the courses in the sibling CourseData checkout, so this is skipped wherever they
/// are missing.
final class StrokeFinderRealRoundTests: XCTestCase {

    private static let projectDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private struct RealRound {
        let round: Round
        let points: [TrackPoint]
        let swings: [StrokeSuggestion]

        func suggestions(onHole hole: Int) -> [StrokeSuggestion] {
            StrokeFinder.suggestions(in: round, holeIndex: hole, points: points, swings: swings, minStop: 30)
        }
    }

    /// A round imported the way the app imports it.
    private func realRound(csv: String, course: String) throws -> RealRound {
        let roundURL = Self.projectDirectory.appendingPathComponent("Data/\(csv)")
        let courseURL = Self.projectDirectory.appendingPathComponent("../CourseData/Data/US/CO/\(course)")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: roundURL.path) &&
                          FileManager.default.fileExists(atPath: courseURL.path), "The real round is not on this machine")

        let course = try JSONDecoder().decode(Course.self, from: Data(contentsOf: courseURL).gzipDecompressed())
        let selection = CourseSelection(course: course, selectedSubCourseIndices: Array(course.subCourses.indices))
        let export = try TrackImporter.read(String(contentsOf: roundURL, encoding: .utf8))
        let (round, _) = try TrackImporter.round(from: export, courseSelection: selection)
        return RealRound(round: round, points: export.points, swings: export.swings)
    }

    /// Walnut Creek, 2026-09-25. Recorded when the watch only reported swings of 10 g or more.
    private func walnutCreek() throws -> RealRound {
        try realRound(csv: "walnut-creek-2026-09-25.csv", course: "Westminster/Walnut-Creek-Golf-Preserve.json.gz")
    }

    /// Coal Creek, 2026-10-02. The first round recorded with the watch's 3 g threshold, so most of
    /// its 698 swings are the small movements of waiting, walking and putting.
    private func coalCreek() throws -> RealRound {
        try realRound(csv: "coal-creek-2026-10-02.csv", course: "Louisville/Coal-Creek-Golf-Course.json.gz")
    }

    private func isFullSwing(_ suggestion: StrokeSuggestion) -> Bool {
        (suggestion.peakG ?? 0) >= StrokeFinder.fullSwingPeak
    }

    // MARK: - Walnut Creek

    func testEveryHoleStartsFromThePath() throws {
        let round = try walnutCreek().round

        XCTAssertEqual(round.holeTimeline.map(\.holeIndex), Array(0..<18))
        // The player's last fix within 10 m of green 1 was at 14:23:28, then they walked to tee 2
        let holeTwo = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-25T14:23:20Z"))
        XCTAssertEqual(round.holeTimeline[1].startedAt.timeIntervalSince(holeTwo), 10, accuracy: 10)
    }

    func testNoHoleOneSuggestionIsAtHoleTwosTee() throws {
        let walnut = try walnutCreek()
        let teeTwo = HoleShape(hole: walnut.round.courseHole(at: 1), course: walnut.round.course)

        for suggestion in walnut.suggestions(onHole: 0) {
            let spot = Coordinate(latitude: suggestion.latitude ?? 0, longitude: suggestion.longitude ?? 0)
            XCTAssertGreaterThan(teeTwo.metersToTee(spot) ?? 0, 20, "\(suggestion.timestamp) is at hole 2's tee")
        }
    }

    /// Swing and stop suggestions per hole when the rules were last tuned. The scorecard had
    /// 4 4 5 3 3 3 2 4 4 4 3 2 4 1 4 3 3 3 full swings, plus putts.
    func testWalnutCreekSuggestionsPerHole() throws {
        let walnut = try walnutCreek()

        let found = (0..<18).map(walnut.suggestions(onHole:))

        XCTAssertEqual(found.map { $0.filter(\.isSwing).count }, [6, 6, 6, 3, 3, 3, 1, 5, 4, 4, 3, 2, 4, 1, 3, 3, 2, 4])
        XCTAssertEqual(found.map { $0.filter { !$0.isSwing }.count }, [1, 1, 1, 1, 1, 1, 2, 2, 1, 1, 1, 3, 5, 1, 1, 1, 1, 2])
    }

    // MARK: - Coal Creek

    /// Full-swing strokes per hole when the rules were last tuned. The player's notes for holes
    /// 1 to 4 had 2, 3, 3 and 7 full swings: on hole 4 the six iron never registered above 9 g
    /// on the watch, and a chunk 42 s after the bunker shot merges into it.
    func testCoalCreekFullSwingsPerHole() throws {
        let coal = try coalCreek()

        let found = (0..<18).map(coal.suggestions(onHole:))

        XCTAssertEqual(found.map { $0.filter(isFullSwing).count }, [2, 3, 3, 5, 3, 3, 2, 4, 5, 3, 3, 4, 2, 3, 3, 2, 2, 5])
    }

    /// Hole 1's drive and wedge: the drive from the Pick & Shovel tee, the wedge from the right
    /// rough 84 m short of the green, both at the swing the watch felt hardest.
    func testCoalCreekHoleOneStrokes() throws {
        let coal = try coalCreek()
        let formatter = ISO8601DateFormatter()
        let drive = try XCTUnwrap(formatter.date(from: "2026-10-02T14:07:46Z"))
        let wedge = try XCTUnwrap(formatter.date(from: "2026-10-02T14:13:03Z"))
        let holeOne = HoleShape(hole: coal.round.courseHole(at: 0), course: coal.round.course)

        let strokes = coal.suggestions(onHole: 0).filter(isFullSwing)

        XCTAssertEqual(strokes.count, 2)
        guard strokes.count == 2 else { return }
        XCTAssertEqual(strokes[0].timestamp.timeIntervalSince(drive), 0, accuracy: 1)
        XCTAssertEqual(strokes[1].timestamp.timeIntervalSince(wedge), 0, accuracy: 1)
        XCTAssertEqual(strokes.map(\.peakG).map { ($0 ?? 0).rounded() }, [18, 24])
        let wedgeSpot = Coordinate(latitude: strokes[1].latitude ?? 0, longitude: strokes[1].longitude ?? 0)
        XCTAssertEqual(holeOne.metersToGreen(wedgeSpot) ?? 0, 84, accuracy: 5)
    }
}
