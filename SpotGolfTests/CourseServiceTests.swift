import XCTest
import CoreLocation
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
                coordinate: CourseCoordinate(latitude: 33.45, longitude: -112.07),
                holes: 18,
                path: "US/AZ/Phoenix/Test-Course.json"
            ),
            CourseIndexEntry(
                name: "Another Course",
                coordinate: CourseCoordinate(latitude: 34.0, longitude: -111.0),
                holes: 9,
                path: "US/AZ/Scottsdale/Another-Course.json"
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
        XCTAssertEqual(loaded?[0].path, "US/AZ/Phoenix/Test-Course.json")
    }

    func testCachedIndexVersionReturnsNilWhenNoCache() {
        XCTAssertNil(service.cachedIndexVersion())
    }

    func testLoadCachedIndexReturnsNilWhenNoCache() throws {
        let loaded = try service.loadCachedIndex()
        XCTAssertNil(loaded)
    }

    // MARK: - Nearby Courses

    private func makeEntry(name: String, lat: Double, lon: Double, holes: Int = 18) -> CourseIndexEntry {
        CourseIndexEntry(
            name: name,
            coordinate: CourseCoordinate(latitude: lat, longitude: lon),
            holes: holes,
            path: "US/ST/City/\(name.replacingOccurrences(of: " ", with: "-")).json"
        )
    }

    func testNearbyCourses() {
        // Phoenix: 33.4484, -112.0740
        let close = makeEntry(name: "Close Course", lat: 33.46, lon: -112.08) // ~1 mile
        let far = makeEntry(name: "Far Course", lat: 34.5, lon: -111.0) // ~100 miles
        service.index = [close, far]

        let location = CLLocation(latitude: 33.4484, longitude: -112.0740)
        let results = service.nearbyCourses(from: location)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].entry.name, "Close Course")
    }

    func testNearbyCourseSortedByDistance() {
        // Two courses within 10 miles but at different distances
        let closer = makeEntry(name: "Closer Course", lat: 33.45, lon: -112.08) // very close
        let farther = makeEntry(name: "Farther Course", lat: 33.50, lon: -112.10) // a few miles
        service.index = [farther, closer] // insert farther first

        let location = CLLocation(latitude: 33.4484, longitude: -112.0740)
        let results = service.nearbyCourses(from: location)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].entry.name, "Closer Course")
        XCTAssertEqual(results[1].entry.name, "Farther Course")
        XCTAssertLessThan(results[0].distanceMiles, results[1].distanceMiles)
    }

    // MARK: - Search Courses

    func testSearchCoursesByName() {
        let course1 = makeEntry(name: "Pine Valley Golf", lat: 33.0, lon: -112.0)
        let course2 = makeEntry(name: "Oak Hills Golf", lat: 34.0, lon: -111.0)
        service.index = [course1, course2]

        let results = service.searchCourses(query: "Pine")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "Pine Valley Golf")
    }

    func testSearchCoursesCaseInsensitive() {
        let course = makeEntry(name: "Pine Valley Golf", lat: 33.0, lon: -112.0)
        service.index = [course]

        let results = service.searchCourses(query: "PINE VALLEY")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "Pine Valley Golf")
    }
}
