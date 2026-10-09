import SwiftData
import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolf

@MainActor
final class HoleStatsTests: XCTestCase {

    /// `PathCourse` with a 30 m fairway 200 m up hole 1, and hole 1 as a par `par`.
    private func selection(par: Int = 4) -> CourseSelection {
        var course = PathCourse.selection.course
        let fairway = Feature(id: 300, type: .fairway, polygon: PathCourse.square(north: 200, east: 0, half: 15))
        course.features.append(fairway)
        course.subCourses[0].holes[0].features.append(fairway.id)
        course.subCourses[0].holes[0].par = par
        return CourseSelection(course: course, selectedSubCourseIndices: [0])
    }

    private func stroke(north: Double, east: Double = 0, type: StrokeType = .regular) -> Stroke {
        let coordinate = PathCourse.coordinate(north: north, east: east)
        return Stroke(coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                      type: type)
    }

    private let tee: (Double, Double) = (0, 0)
    private let fairway: (Double, Double) = (200, 0)
    private let rough: (Double, Double) = (200, 40)
    private let green: (Double, Double) = (300, 0)

    private func stats(_ strokes: [Stroke], par: Int = 4) -> HoleStats? {
        let round = Round(courseSelection: selection(par: par))
        round.holes = [RoundHole(strokes: strokes)]
        return round.workOutStats(holeIndex: 0)
    }

    func testNoStrokesHasNoStats() {
        XCTAssertNil(stats([]))
    }

    func testFairwayAndGreenInRegulationWithTwoPutts() {
        let result = stats([stroke(north: 0), stroke(north: 200), stroke(north: 290), stroke(north: 300)])

        XCTAssertEqual(result, HoleStats(putts: 2, fairway: true, green: true))
    }

    func testMissedFairwayAndGreen() {
        let result = stats([stroke(north: 0), stroke(north: 200, east: 40), stroke(north: 250), stroke(north: 300)])

        XCTAssertEqual(result, HoleStats(putts: 1, fairway: false, green: false))
    }

    func testDrivingTheGreenHitsTheFairway() {
        let result = stats([stroke(north: 0), stroke(north: 300)])

        XCTAssertEqual(result?.fairway, true)
        XCTAssertEqual(result?.green, true)
    }

    func testAPenaltyMarkAfterTheTeeShotMissesTheFairway() {
        // The tee shot went in the water, marked on the fairway, and the drop is stroke 3
        let result = stats([stroke(north: 0), stroke(north: 200, type: .penalty), stroke(north: 200), stroke(north: 300)])

        XCTAssertEqual(result?.fairway, false)
        // Reaching the green took three strokes on a par 4
        XCTAssertEqual(result?.green, false)
        XCTAssertEqual(result?.putts, 1)
    }

    func testAParThreeHasNoFairway() {
        let result = stats([stroke(north: 0), stroke(north: 300)], par: 3)

        XCTAssertNil(result?.fairway)
        XCTAssertEqual(result?.green, true)
    }

    func testOneStrokeHasNoFairwayYet() {
        XCTAssertNil(stats([stroke(north: 0)])?.fairway)
    }

    func testStoreSavesStatsOnEveryStrokeChange() throws {
        let container = Storage.inMemoryContainer()
        let store = RoundStore(context: ModelContext(container))
        let round = store.startRound(courseSelection: selection())
        let teeShot = stroke(north: 0)
        let approach = stroke(north: 200, east: 40)

        store.addStroke(to: round.id, holeIndex: 0, stroke: teeShot)
        XCTAssertEqual(round.holes[0].stats, HoleStats(putts: 0, fairway: nil, green: false))

        store.addStroke(to: round.id, holeIndex: 0, stroke: approach)
        XCTAssertEqual(round.holes[0].stats?.fairway, false)

        let fairwayCoordinate = PathCourse.coordinate(north: 200, east: 0)
        store.moveStroke(approach, to: CLLocationCoordinate2D(latitude: fairwayCoordinate.latitude,
                                                              longitude: fairwayCoordinate.longitude), in: round.id)
        XCTAssertEqual(round.holes[0].stats?.fairway, true)

        store.setStrokeType(strokeID: approach.id, type: .penalty, in: round.id)
        XCTAssertEqual(round.holes[0].stats?.fairway, false)

        store.removeStroke(approach, from: round.id)
        XCTAssertNil(round.holes[0].stats?.fairway)

        store.removeStroke(teeShot, from: round.id)
        XCTAssertNil(round.holes[0].stats)
    }

    // MARK: - Tees

    func testComboTeeYardsComeFromTheTeeItNames() {
        var course = CourseSelection.test.course
        course.tees = [TeeDefinition(name: "Blue", color: "#0000FF"), TeeDefinition(name: "White", color: "#FFFFFF")]
        course.comboTees = [ComboTeeDefinition(name: "Blue/White", tees: ["Blue", "White"])]
        course.subCourses[0].holes[0].yardages = ["Blue": 400, "White": 360]
        course.subCourses[0].holes[0].comboTees = ["Blue/White": "White"]

        let selection = CourseSelection(course: course, selectedSubCourseIndices: [0, 1], teeName: "Blue/White")

        XCTAssertEqual(selection.teeNames, ["Blue", "White", "Blue/White"])
        XCTAssertEqual(selection.yards(holeIndex: 0), 360)
        XCTAssertEqual(selection.teeColor("Blue/White"), "#0000FF")
        XCTAssertEqual(selection.trimmed.teeName, "Blue/White")
        XCTAssertEqual(selection.trimmed.teeNames, ["Blue", "White", "Blue/White"])
    }

    func testASelectionSavedWithoutATeeDecodes() throws {
        let data = try JSONEncoder().encode(CourseSelection.test)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "teeName")

        let decoded = try JSONDecoder().decode(CourseSelection.self, from: JSONSerialization.data(withJSONObject: json))

        XCTAssertNil(decoded.teeName)
        XCTAssertNil(decoded.yards(holeIndex: 0))
    }
}
