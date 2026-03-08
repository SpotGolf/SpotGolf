import XCTest
import CoreLocation
@testable import SpotGolf

final class HoleAdvancerTests: XCTestCase {

    // MARK: - Helpers

    private func makeHole(number: Int, tees: [String: CourseCoordinate]) -> CourseHole {
        CourseHole(
            id: "hole-\(number)",
            number: number,
            par: 4,
            maleHandicap: nil,
            femaleHandicap: nil,
            green: CourseGreen(
                front: CourseCoordinate(latitude: 0, longitude: 0),
                middle: CourseCoordinate(latitude: 0, longitude: 0),
                back: CourseCoordinate(latitude: 0, longitude: 0)
            ),
            tees: tees,
            yardages: [:],
            features: []
        )
    }

    private func makeSelection(holes: [CourseHole]) -> CourseSelection {
        let subCourse = SubCourse(name: "Test", holes: holes)
        let course = Course(
            id: "test-course",
            name: "Test Course",
            clubName: "Test Club",
            location: CourseLocation(
                address: nil,
                city: "Test",
                coordinate: CourseCoordinate(latitude: 0, longitude: 0),
                country: "US",
                state: "TX"
            ),
            subCourses: [subCourse]
        )
        return CourseSelection(course: course, selectedSubCourseIndices: [0])
    }

    // MARK: - Tests

    func testDetectsCorrectHole() {
        // Hole 1 tee at (33.0, -97.0), Hole 2 tee at (33.001, -97.0), Hole 3 tee at (33.002, -97.0)
        let holes = [
            makeHole(number: 1, tees: ["blue": CourseCoordinate(latitude: 33.0, longitude: -97.0)]),
            makeHole(number: 2, tees: ["blue": CourseCoordinate(latitude: 33.001, longitude: -97.0)]),
            makeHole(number: 3, tees: ["blue": CourseCoordinate(latitude: 33.002, longitude: -97.0)]),
        ]
        let selection = makeSelection(holes: holes)

        // User is near hole 2 tee (index 1)
        let userLocation = CLLocation(latitude: 33.001, longitude: -97.0)
        let result = HoleAdvancer.detectHole(location: userLocation, courseSelection: selection)

        XCTAssertEqual(result, 1)
    }

    func testReturnsNilWhenNotNearAnyTee() {
        let holes = [
            makeHole(number: 1, tees: ["blue": CourseCoordinate(latitude: 33.0, longitude: -97.0)]),
            makeHole(number: 2, tees: ["blue": CourseCoordinate(latitude: 33.001, longitude: -97.0)]),
        ]
        let selection = makeSelection(holes: holes)

        // User is far from all tees
        let userLocation = CLLocation(latitude: 34.0, longitude: -96.0)
        let result = HoleAdvancer.detectHole(location: userLocation, courseSelection: selection)

        XCTAssertNil(result)
    }

    func testManualOverridePausesAutoAdvance() {
        var advancer = HoleAdvancer()
        XCTAssertFalse(advancer.isPaused)

        advancer.pause()
        XCTAssertTrue(advancer.isPaused)
    }

    func testResumeReEnablesAutoAdvance() {
        var advancer = HoleAdvancer()
        advancer.pause()
        XCTAssertTrue(advancer.isPaused)

        advancer.resume()
        XCTAssertFalse(advancer.isPaused)
    }
}
