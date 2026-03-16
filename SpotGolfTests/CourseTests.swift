import XCTest
import CoreLocation
import CourseData
@testable import SpotGolf

final class CourseTests: XCTestCase {

    // MARK: - Test JSON

    private let fullCourseJSON = """
    {
        "id": "00000000-0000-0000-0000-000000000001",
        "name": "Championship Course",
        "clubName": "Pine Valley Golf Club",
        "location": {
            "address": "1 Pine Valley Rd",
            "city": "Pine Valley",
            "coordinates": [39.7879, -74.9681],
            "country": "US",
            "state": "NJ"
        },
        "features": [
            {
                "id": 10,
                "type": "bunker",
                "polygon": [
                    [39.7877, -74.9683],
                    [39.7877, -74.9682],
                    [39.7878, -74.9682],
                    [39.7878, -74.9683],
                    [39.7877, -74.9683]
                ]
            },
            {
                "id": 11,
                "type": "green",
                "polygon": [
                    [39.7880, -74.9681],
                    [39.7880, -74.9679],
                    [39.7882, -74.9679],
                    [39.7882, -74.9681],
                    [39.7880, -74.9681]
                ]
            }
        ],
        "subCourses": [
            {
                "id": "00000000-0000-0000-0000-000000000010",
                "name": "Front Nine",
                "holes": [
                    {
                        "number": 1,
                        "par": 4,
                        "maleHandicap": 7,
                        "femaleHandicap": 9,
                        "yardages": {
                            "blue": 425,
                            "white": 400
                        },
                        "features": [10, 11],
                        "tees": {
                            "blue": 12,
                            "white": 13
                        },
                        "centerline": []
                    }
                ],
                "tees": {}
            },
            {
                "id": "00000000-0000-0000-0000-000000000011",
                "name": "Back Nine",
                "holes": [
                    {
                        "number": 10,
                        "par": 5,
                        "yardages": {
                            "blue": 550
                        },
                        "features": [11],
                        "tees": {
                            "blue": 14
                        },
                        "centerline": []
                    }
                ],
                "tees": {}
            }
        ]
    }
    """

    private let indexEntryJSON = """
    {
        "name": "Championship Course",
        "coordinate": { "latitude": 39.7879, "longitude": -74.9681 },
        "holes": 18,
        "path": "US/NJ/Pine Valley/Championship-Course.json.gz"
    }
    """

    // MARK: - Tests

    func testDecodeCourseFromJSON() throws {
        let data = fullCourseJSON.data(using: .utf8)!
        let course = try JSONDecoder().decode(Course.self, from: data)

        XCTAssertEqual(course.name, "Championship Course")
        XCTAssertEqual(course.clubName, "Pine Valley Golf Club")
        XCTAssertEqual(course.location.city, "Pine Valley")
        XCTAssertEqual(course.location.state, "NJ")
        XCTAssertEqual(course.location.country, "US")
        XCTAssertEqual(course.location.address, "1 Pine Valley Rd")
        XCTAssertEqual(course.location.coordinate.latitude, 39.7879, accuracy: 0.0001)
        XCTAssertEqual(course.location.coordinate.longitude, -74.9681, accuracy: 0.0001)
        XCTAssertEqual(course.subCourses.count, 2)

        let hole = course.subCourses[0].holes[0]
        XCTAssertEqual(hole.number, 1)
        XCTAssertEqual(hole.par, 4)
        XCTAssertEqual(hole.maleHandicap, 7)
        XCTAssertEqual(hole.femaleHandicap, 9)
        XCTAssertEqual(hole.yardages?["blue"], 425)
        XCTAssertEqual(hole.yardages?["white"], 400)
        XCTAssertEqual(hole.features?.count, 2)

        XCTAssertEqual(course.features.count, 2)
        XCTAssertEqual(course.features[0].id, 10)
        XCTAssertEqual(course.features[0].type, .bunker)
        XCTAssertEqual(course.features[1].id, 11)
        XCTAssertEqual(course.features[1].type, .green)
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
        XCTAssertEqual(entry.coordinate.latitude, 39.7879, accuracy: 0.0001)
        XCTAssertEqual(entry.coordinate.longitude, -74.9681, accuracy: 0.0001)
        XCTAssertEqual(entry.holes, 18)
        XCTAssertEqual(entry.path, "US/NJ/Pine Valley/Championship-Course.json.gz")
    }

    func testGreenResolution() throws {
        let data = fullCourseJSON.data(using: .utf8)!
        let course = try JSONDecoder().decode(Course.self, from: data)

        let hole = course.subCourses[0].holes[0]
        let green = hole.green(from: course.features)

        XCTAssertNotNil(green)
        XCTAssertEqual(green?.id, 11)
        XCTAssertEqual(green?.type, .green)
    }

    func testCourseSelectionOrderedHoles() throws {
        let data = fullCourseJSON.data(using: .utf8)!
        let course = try JSONDecoder().decode(Course.self, from: data)

        // Select both sub-courses
        let selection = CourseSelection(course: course, selectedSubCourseIndices: [0, 1])
        let holes = selection.orderedHoles

        XCTAssertEqual(holes.count, 2)
        XCTAssertEqual(holes[0].number, 1)
        XCTAssertEqual(holes[1].number, 10)
    }

    func testCourseSelectionSingleSubCourse() throws {
        let data = fullCourseJSON.data(using: .utf8)!
        let course = try JSONDecoder().decode(Course.self, from: data)

        // Select only the back nine
        let selection = CourseSelection(course: course, selectedSubCourseIndices: [1])
        let holes = selection.orderedHoles

        XCTAssertEqual(holes.count, 1)
        XCTAssertEqual(holes[0].number, 10)
        XCTAssertEqual(holes[0].par, 5)
    }
}
