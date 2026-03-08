import XCTest
import CoreLocation
@testable import SpotGolf

final class CourseTests: XCTestCase {

    // MARK: - Test JSON

    private let fullCourseJSON = """
    {
        "id": "course-123",
        "name": "Championship Course",
        "clubName": "Pine Valley Golf Club",
        "location": {
            "address": "1 Pine Valley Rd",
            "city": "Pine Valley",
            "coordinate": { "latitude": 39.7879, "longitude": -74.9681 },
            "country": "US",
            "state": "NJ"
        },
        "subCourses": [
            {
                "name": "Front Nine",
                "holes": [
                    {
                        "id": "hole-1",
                        "number": 1,
                        "par": 4,
                        "maleHandicap": 7,
                        "femaleHandicap": 9,
                        "green": {
                            "front": { "latitude": 39.7880, "longitude": -74.9680 },
                            "middle": { "latitude": 39.7881, "longitude": -74.9680 },
                            "back": { "latitude": 39.7882, "longitude": -74.9680 }
                        },
                        "tees": {
                            "blue": { "latitude": 39.7870, "longitude": -74.9690 },
                            "white": { "latitude": 39.7871, "longitude": -74.9690 }
                        },
                        "yardages": {
                            "blue": 425,
                            "white": 400
                        },
                        "features": [
                            {
                                "id": "bunker-1",
                                "type": "bunker",
                                "front": { "latitude": 39.7877, "longitude": -74.9683 },
                                "back": { "latitude": 39.7878, "longitude": -74.9682 }
                            },
                            {
                                "id": "water-1",
                                "type": "water",
                                "front": { "latitude": 39.7875, "longitude": -74.9685 },
                                "back": { "latitude": 39.7876, "longitude": -74.9684 }
                            }
                        ]
                    }
                ]
            },
            {
                "name": "Back Nine",
                "holes": [
                    {
                        "id": "hole-10",
                        "number": 10,
                        "par": 5,
                        "green": {
                            "front": { "latitude": 39.7890, "longitude": -74.9670 },
                            "middle": { "latitude": 39.7891, "longitude": -74.9670 },
                            "back": { "latitude": 39.7892, "longitude": -74.9670 }
                        },
                        "tees": {
                            "blue": { "latitude": 39.7885, "longitude": -74.9675 }
                        },
                        "yardages": {
                            "blue": 550
                        },
                        "features": []
                    }
                ]
            }
        ]
    }
    """

    private let indexEntryJSON = """
    {
        "name": "Championship Course",
        "coordinate": { "latitude": 39.7879, "longitude": -74.9681 },
        "holes": 18,
        "path": "US/NJ/Pine Valley/Championship-Course.json"
    }
    """

    // MARK: - Tests

    func testDecodeCourseFromJSON() throws {
        let data = fullCourseJSON.data(using: .utf8)!
        let course = try JSONDecoder().decode(Course.self, from: data)

        XCTAssertEqual(course.id, "course-123")
        XCTAssertEqual(course.name, "Championship Course")
        XCTAssertEqual(course.clubName, "Pine Valley Golf Club")
        XCTAssertEqual(course.location.city, "Pine Valley")
        XCTAssertEqual(course.location.state, "NJ")
        XCTAssertEqual(course.location.country, "US")
        XCTAssertEqual(course.location.address, "1 Pine Valley Rd")
        XCTAssertEqual(course.location.coordinate.latitude, 39.7879)
        XCTAssertEqual(course.location.coordinate.longitude, -74.9681)
        XCTAssertEqual(course.subCourses.count, 2)

        let hole = course.subCourses[0].holes[0]
        XCTAssertEqual(hole.id, "hole-1")
        XCTAssertEqual(hole.number, 1)
        XCTAssertEqual(hole.par, 4)
        XCTAssertEqual(hole.maleHandicap, 7)
        XCTAssertEqual(hole.femaleHandicap, 9)
        XCTAssertEqual(hole.green.front.latitude, 39.7880)
        XCTAssertEqual(hole.green.middle.latitude, 39.7881)
        XCTAssertEqual(hole.green.back.latitude, 39.7882)
        XCTAssertEqual(hole.tees["blue"]?.latitude, 39.7870)
        XCTAssertEqual(hole.tees["white"]?.latitude, 39.7871)
        XCTAssertEqual(hole.yardages["blue"], 425)
        XCTAssertEqual(hole.yardages["white"], 400)
        XCTAssertEqual(hole.features.count, 2)
        XCTAssertEqual(hole.features[0].type, .bunker)
        XCTAssertEqual(hole.features[1].type, .water)
    }

    func testDecodeSubCourseWithName() throws {
        let data = fullCourseJSON.data(using: .utf8)!
        let course = try JSONDecoder().decode(Course.self, from: data)

        XCTAssertEqual(course.subCourses[0].name, "Front Nine")
        XCTAssertEqual(course.subCourses[1].name, "Back Nine")
    }

    func testDecodeIndexEntry() throws {
        let data = indexEntryJSON.data(using: .utf8)!
        let entry = try JSONDecoder().decode(CourseIndexEntry.self, from: data)

        XCTAssertEqual(entry.name, "Championship Course")
        XCTAssertEqual(entry.coordinate.latitude, 39.7879)
        XCTAssertEqual(entry.coordinate.longitude, -74.9681)
        XCTAssertEqual(entry.holes, 18)
        XCTAssertEqual(entry.path, "US/NJ/Pine Valley/Championship-Course.json")
        XCTAssertEqual(entry.city, "Pine Valley")
        XCTAssertEqual(entry.state, "NJ")
        XCTAssertEqual(entry.country, "US")
    }

    func testCourseHoleCoordinateAccessors() throws {
        let data = fullCourseJSON.data(using: .utf8)!
        let course = try JSONDecoder().decode(Course.self, from: data)
        let hole = course.subCourses[0].holes[0]

        // Test CourseCoordinate CLLocation conversions
        let greenFront = hole.green.front
        XCTAssertEqual(greenFront.clLocationCoordinate2D.latitude, 39.7880)
        XCTAssertEqual(greenFront.clLocationCoordinate2D.longitude, -74.9680)
        XCTAssertEqual(greenFront.clLocation.coordinate.latitude, 39.7880)
        XCTAssertEqual(greenFront.clLocation.coordinate.longitude, -74.9680)

        // Test feature middle computed property
        let bunker = hole.features[0]
        let expectedMiddleLat = (bunker.front.latitude + bunker.back.latitude) / 2.0
        let expectedMiddleLon = (bunker.front.longitude + bunker.back.longitude) / 2.0
        XCTAssertEqual(bunker.middle.coordinate.latitude, expectedMiddleLat, accuracy: 0.0001)
        XCTAssertEqual(bunker.middle.coordinate.longitude, expectedMiddleLon, accuracy: 0.0001)
    }

    func testCourseSelectionOrderedHoles() throws {
        let data = fullCourseJSON.data(using: .utf8)!
        let course = try JSONDecoder().decode(Course.self, from: data)

        // Select both sub-courses
        let selection = CourseSelection(course: course, selectedSubCourseIndices: [0, 1])
        let holes = selection.orderedHoles

        XCTAssertEqual(holes.count, 2)
        XCTAssertEqual(holes[0].id, "hole-1")
        XCTAssertEqual(holes[0].number, 1)
        XCTAssertEqual(holes[1].id, "hole-10")
        XCTAssertEqual(holes[1].number, 10)
    }

    func testCourseSelectionSingleSubCourse() throws {
        let data = fullCourseJSON.data(using: .utf8)!
        let course = try JSONDecoder().decode(Course.self, from: data)

        // Select only the back nine
        let selection = CourseSelection(course: course, selectedSubCourseIndices: [1])
        let holes = selection.orderedHoles

        XCTAssertEqual(holes.count, 1)
        XCTAssertEqual(holes[0].id, "hole-10")
        XCTAssertEqual(holes[0].par, 5)
    }
}
