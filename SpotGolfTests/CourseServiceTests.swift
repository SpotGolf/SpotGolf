import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolf

@MainActor
final class CourseServiceTests: XCTestCase {

    private var service: CourseService!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CourseServiceTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        service = CourseService(cacheDirectory: tempDir)
    }

    override func tearDown() async throws {
        service = nil
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        try await super.tearDown()
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
            name: "Test Course",
            clubName: "Test Club",
            location: CourseLocation(address: "123 Main St", city: "Phoenix", state: "AZ", country: "US",
                                     coordinate: Coordinate(lat: 33.45, lon: -112.07)),
            subCourses: [SubCourse(name: "Front", holes: [Hole(number: 1, par: 4)])]
        )
        let data = try JSONEncoder().encode(course)
        let path = "us/az/test-course-1.json.gz"
        let compressed = try data.gzipCompressed()
        try service.cacheCourseData(compressed, forPath: path)

        let loaded = try service.loadCachedCourse(path: path)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.name, "Test Course")
        XCTAssertEqual(loaded?.subCourses.count, 1)
    }

    func testLoadCachedCourseThrowsCorruptDataWhenFileIsNotGzip() throws {
        let path = "us/az/not-gzip.json.gz"
        try service.cacheCourseData(Data("404: Not Found".utf8), forPath: path)

        XCTAssertThrowsError(try service.loadCachedCourse(path: path)) { error in
            XCTAssertEqual(error as? CourseServiceError, .corruptData)
        }
    }

    func testDecodeCourseThrowsCorruptDataWhenJSONIsNotACourse() throws {
        let compressed = try Data("{\"name\": 1}".utf8).gzipCompressed()

        XCTAssertThrowsError(try CourseService.decodeCourse(compressed)) { error in
            XCTAssertEqual(error as? CourseServiceError, .corruptData)
        }
    }

    // MARK: - fetchCourse

    func testFetchCourseThrowsCourseMissingOn404() async throws {
        StubURLProtocol.install(status: 404, body: Data("404: Not Found".utf8))
        defer { StubURLProtocol.uninstall() }

        let path = "us/az/missing.json.gz"
        do {
            _ = try await service.fetchCourse(path: path)
            XCTFail("fetchCourse should throw")
        } catch {
            XCTAssertEqual(error as? CourseServiceError, .courseMissing)
        }
        XCTAssertNil(try service.loadCachedCourse(path: path), "a 404 body must not be cached")
    }

    func testFetchCourseThrowsCorruptDataWhenBodyIsNotGzip() async throws {
        StubURLProtocol.install(status: 200, body: Data("not gzip".utf8))
        defer { StubURLProtocol.uninstall() }

        do {
            _ = try await service.fetchCourse(path: "us/az/corrupt.json.gz")
            XCTFail("fetchCourse should throw")
        } catch {
            XCTAssertEqual(error as? CourseServiceError, .corruptData)
        }
    }

    func testFetchCourseFallsBackToCacheOn404() async throws {
        let course = Course(
            name: "Cached Course",
            clubName: "Test Club",
            location: CourseLocation(address: "123 Main St", city: "Phoenix", state: "AZ", country: "US",
                                     coordinate: Coordinate(lat: 33.45, lon: -112.07)),
            subCourses: []
        )
        let path = "us/az/cached.json.gz"
        try service.cacheCourseData(try JSONEncoder().encode(course).gzipCompressed(), forPath: path)

        StubURLProtocol.install(status: 404, body: Data())
        defer { StubURLProtocol.uninstall() }

        let loaded = try await service.fetchCourse(path: path)
        XCTAssertEqual(loaded.name, "Cached Course")
    }

    func testErrorDescriptions() {
        XCTAssertEqual(CourseServiceError.courseMissing.localizedDescription, "the course data is missing")
        XCTAssertEqual(CourseServiceError.corruptData.localizedDescription, "the data is corrupt")
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
            CourseIndexEntry(name: "Test Course", coordinate: IndexCoordinate(latitude: 33.45, longitude: -112.07),
                             holes: 18, path: "US/AZ/Phoenix/Test-Course.json.gz"),
            CourseIndexEntry(name: "Another Course", coordinate: IndexCoordinate(latitude: 34.0, longitude: -111.0),
                             holes: 9, path: "US/AZ/Scottsdale/Another-Course.json.gz")
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
            coordinate: IndexCoordinate(latitude: lat, longitude: lon),
            holes: holes,
            path: "US/ST/City/\(name.replacingOccurrences(of: " ", with: "-")).json.gz"
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

// MARK: - StubURLProtocol

/// Answers every request on the shared session with one canned response.
private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var status = 200
    nonisolated(unsafe) private static var body = Data()

    static func install(status: Int, body: Data) {
        self.status = status
        self.body = body
        URLProtocol.registerClass(StubURLProtocol.self)
    }

    static func uninstall() {
        URLProtocol.unregisterClass(StubURLProtocol.self)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
