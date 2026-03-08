import XCTest
@testable import SpotGolf

@MainActor
final class CourseServiceTests: XCTestCase {

    private var service: CourseService!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CourseServiceTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        service = CourseService(cacheDirectory: tempDir)
    }

    override func tearDown() {
        service = nil
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    // MARK: - testParseIndexVersion

    func testParseIndexVersionWithNewline() {
        XCTAssertEqual(CourseService.parseVersion("42\n"), 42)
    }

    func testParseIndexVersionPlain() {
        XCTAssertEqual(CourseService.parseVersion("1"), 1)
    }

    func testParseIndexVersionInvalidString() {
        XCTAssertNil(CourseService.parseVersion("abc"))
    }

    func testParseIndexVersionEmptyString() {
        XCTAssertNil(CourseService.parseVersion(""))
    }

    func testParseIndexVersionWithWhitespace() {
        XCTAssertEqual(CourseService.parseVersion("  7  \n"), 7)
    }

    // MARK: - testCacheAndLoadCourseData

    func testCacheAndLoadCourseData() throws {
        let course = Course(
            id: "test-course-1",
            name: "Test Course",
            clubName: "Test Club",
            location: CourseLocation(
                address: "123 Main St",
                city: "Phoenix",
                coordinate: CourseCoordinate(latitude: 33.45, longitude: -112.07),
                country: "US",
                state: "AZ"
            ),
            subCourses: [
                SubCourse(name: "Front", holes: [
                    CourseHole(
                        id: "hole-1",
                        number: 1,
                        par: 4,
                        maleHandicap: 1,
                        femaleHandicap: 1,
                        green: CourseGreen(
                            front: CourseCoordinate(latitude: 33.451, longitude: -112.071),
                            middle: CourseCoordinate(latitude: 33.452, longitude: -112.072),
                            back: CourseCoordinate(latitude: 33.453, longitude: -112.073)
                        ),
                        tees: ["blue": CourseCoordinate(latitude: 33.449, longitude: -112.075)],
                        yardages: ["blue": 400],
                        features: []
                    )
                ])
            ]
        )

        let data = try JSONEncoder().encode(course)
        let path = "us/az/test-course-1.json"

        try service.cacheCourseData(data, forPath: path)

        let loaded = try service.loadCachedCourse(path: path)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, "test-course-1")
        XCTAssertEqual(loaded?.name, "Test Course")
        XCTAssertEqual(loaded?.clubName, "Test Club")
        XCTAssertEqual(loaded?.subCourses.count, 1)
        XCTAssertEqual(loaded?.subCourses[0].holes.count, 1)
    }

    // MARK: - testCacheSizeEnforcement

    func testCacheSizeEnforcement() throws {
        // Create data that's about 1MB each, fill past 5MB
        let chunkSize = 1_100_000
        let largeData = Data(repeating: 0x41, count: chunkSize)

        for i in 0..<6 {
            let path = "us/az/course-\(i).json"
            try service.cacheCourseData(largeData, forPath: path)
            // Small delay so file access dates differ
        }

        let sizeAfter = service.cacheSizeBytes()
        XCTAssertLessThanOrEqual(sizeAfter, CourseService.maxCacheBytes,
            "Cache size \(sizeAfter) should be at most \(CourseService.maxCacheBytes)")
    }

    // MARK: - testCacheIndexAndLoad

    func testCacheIndexAndLoad() throws {
        let entries = [
            CourseIndexEntry(
                name: "Test Course",
                clubName: "Test Club",
                location: CourseIndexLocation(
                    coordinate: CourseCoordinate(latitude: 33.45, longitude: -112.07),
                    city: "Phoenix",
                    state: "AZ",
                    country: "US"
                ),
                path: "us/az/test-course.json"
            ),
            CourseIndexEntry(
                name: "Another Course",
                clubName: "Another Club",
                location: CourseIndexLocation(
                    coordinate: CourseCoordinate(latitude: 34.0, longitude: -111.0),
                    city: "Scottsdale",
                    state: "AZ",
                    country: "US"
                ),
                path: "us/az/another-course.json"
            )
        ]

        let data = try JSONEncoder().encode(entries)
        try service.cacheIndex(data: data, version: 5)

        let cachedVersion = service.cachedIndexVersion()
        XCTAssertEqual(cachedVersion, 5)

        let loaded = try service.loadCachedIndex()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 2)
        XCTAssertEqual(loaded?[0].name, "Test Course")
        XCTAssertEqual(loaded?[1].name, "Another Course")
        XCTAssertEqual(loaded?[0].path, "us/az/test-course.json")
    }

    func testCachedIndexVersionReturnsNilWhenNoCache() {
        XCTAssertNil(service.cachedIndexVersion())
    }

    func testLoadCachedIndexReturnsNilWhenNoCache() throws {
        let loaded = try service.loadCachedIndex()
        XCTAssertNil(loaded)
    }
}
