# Course Data Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Integrate golf course data from the SpotGolf/CourseData GitHub repository so users can search/find nearby courses, view distances to greens and features, and auto-advance holes via GPS.

**Architecture:** New `Course` model hierarchy maps the CourseData JSON. A `CourseService` handles fetching/caching from GitHub. Course data attaches to `Round` and syncs to watchOS. A `HoleAdvancer` monitors GPS to auto-advance holes. Distance info displays on iOS map (always visible) and watchOS swing-away screen (dismiss button replaces timer).

**Tech Stack:** Swift, SwiftUI, CoreLocation, MapKit, WatchConnectivity, Foundation (URLSession, Compression)

---

### Task 1: Course Data Models

Create Swift models that decode the CourseData JSON format.

**Files:**
- Create: `Shared/Models/Course.swift`
- Test: `SpotGolfTests/CourseTests.swift`

**Step 1: Write the failing test**

```swift
// SpotGolfTests/CourseTests.swift
import XCTest
import CoreLocation
@testable import SpotGolf

final class CourseTests: XCTestCase {

    func testDecodeCourseFromJSON() throws {
        let json = """
        {
          "id": "0E60C161-A064-4F99-BB0A-03CB0968D97D",
          "name": "Broadlands Golf Course",
          "clubName": "Broadlands Golf Course",
          "location": {
            "address": "4380 W 144th Ave, Broomfield, CO 80023, USA",
            "city": "Broomfield",
            "coordinate": { "latitude": 39.956543, "longitude": -105.040375 },
            "country": "United States",
            "state": "CO"
          },
          "subCourses": [
            {
              "name": "Front",
              "holes": [
                {
                  "id": "FA888A9A-0C43-4E6A-BD70-AF52C7854650",
                  "number": 1,
                  "par": 4,
                  "maleHandicap": 13,
                  "femaleHandicap": 9,
                  "green": {
                    "front": { "latitude": 39.9550, "longitude": -105.0456 },
                    "middle": { "latitude": 39.9550, "longitude": -105.0458 },
                    "back": { "latitude": 39.9549, "longitude": -105.0460 }
                  },
                  "tees": {
                    "Black": { "latitude": 39.9555, "longitude": -105.0415 },
                    "Blue": { "latitude": 39.9554, "longitude": -105.0422 }
                  },
                  "yardages": {
                    "Black": 405,
                    "Blue": 343
                  },
                  "features": [
                    {
                      "id": "7AE5F3EA-FE4C-46B3-B9E2-B7CF07D6324B",
                      "type": "bunker",
                      "front": { "latitude": 39.9552, "longitude": -105.0443 },
                      "back": { "latitude": 39.9552, "longitude": -105.0446 }
                    }
                  ]
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let course = try JSONDecoder().decode(Course.self, from: json)
        XCTAssertEqual(course.id, "0E60C161-A064-4F99-BB0A-03CB0968D97D")
        XCTAssertEqual(course.name, "Broadlands Golf Course")
        XCTAssertEqual(course.location.city, "Broomfield")
        XCTAssertEqual(course.location.coordinate.latitude, 39.956543)
        XCTAssertEqual(course.subCourses.count, 1)

        let hole = course.subCourses[0].holes[0]
        XCTAssertEqual(hole.number, 1)
        XCTAssertEqual(hole.par, 4)
        XCTAssertEqual(hole.green.front.latitude, 39.9550)
        XCTAssertEqual(hole.tees["Black"]?.latitude, 39.9555)
        XCTAssertEqual(hole.yardages["Black"], 405)
        XCTAssertEqual(hole.features.count, 1)
        XCTAssertEqual(hole.features[0].type, .bunker)
    }

    func testDecodeSubCourseWithName() throws {
        let json = """
        {
          "id": "TEST",
          "name": "Test Course",
          "clubName": "Test Club",
          "location": {
            "address": "123 Main St",
            "city": "Denver",
            "coordinate": { "latitude": 39.0, "longitude": -105.0 },
            "country": "United States",
            "state": "CO"
          },
          "subCourses": [
            { "name": "Front", "holes": [] },
            { "name": "Back", "holes": [] }
          ]
        }
        """.data(using: .utf8)!

        let course = try JSONDecoder().decode(Course.self, from: json)
        XCTAssertEqual(course.subCourses[0].name, "Front")
        XCTAssertEqual(course.subCourses[1].name, "Back")
    }

    func testDecodeIndexEntry() throws {
        let json = """
        {
          "name": "Broadlands Golf Course",
          "clubName": "Broadlands Golf Course",
          "location": {
            "coordinate": { "latitude": 39.956543, "longitude": -105.040375 },
            "city": "Broomfield",
            "state": "CO",
            "country": "United States"
          },
          "path": "US/CO/Broomfield/Broadlands-Golf-Course.json"
        }
        """.data(using: .utf8)!

        let entry = try JSONDecoder().decode(CourseIndexEntry.self, from: json)
        XCTAssertEqual(entry.name, "Broadlands Golf Course")
        XCTAssertEqual(entry.path, "US/CO/Broomfield/Broadlands-Golf-Course.json")
        XCTAssertEqual(entry.location.city, "Broomfield")
    }

    func testCourseHoleCoordinateAccessors() throws {
        let coord = CourseCoordinate(latitude: 39.95, longitude: -105.04)
        let location = coord.clLocation
        XCTAssertEqual(location.coordinate.latitude, 39.95, accuracy: 0.001)
        XCTAssertEqual(location.coordinate.longitude, -105.04, accuracy: 0.001)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpotGolfTests/CourseTests 2>&1 | tail -20`
Expected: FAIL — Course type not found

**Step 3: Write minimal implementation**

```swift
// Shared/Models/Course.swift
import Foundation
import CoreLocation

// MARK: - Coordinate

struct CourseCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double

    var clLocationCoordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var clLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Feature

struct CourseFeature: Codable, Identifiable, Equatable {
    let id: String
    let type: FeatureType
    let front: CourseCoordinate
    let back: CourseCoordinate

    enum FeatureType: String, Codable {
        case bunker
        case water
    }

    var middle: CLLocation {
        CLLocation(
            latitude: (front.latitude + back.latitude) / 2,
            longitude: (front.longitude + back.longitude) / 2
        )
    }
}

// MARK: - Green

struct CourseGreen: Codable, Equatable {
    let front: CourseCoordinate
    let middle: CourseCoordinate
    let back: CourseCoordinate
}

// MARK: - Course Hole

struct CourseHole: Codable, Identifiable, Equatable {
    let id: String
    let number: Int
    let par: Int
    let maleHandicap: Int?
    let femaleHandicap: Int?
    let green: CourseGreen
    let tees: [String: CourseCoordinate]
    let yardages: [String: Int]
    let features: [CourseFeature]
}

// MARK: - Sub-Course

struct SubCourse: Codable, Equatable {
    let name: String?
    let holes: [CourseHole]
}

// MARK: - Course Location

struct CourseLocation: Codable, Equatable {
    let address: String?
    let city: String
    let coordinate: CourseCoordinate
    let country: String
    let state: String
}

// MARK: - Course

struct Course: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let clubName: String
    let location: CourseLocation
    let subCourses: [SubCourse]
}

// MARK: - Index Entry

struct CourseIndexEntry: Codable, Equatable {
    let name: String
    let clubName: String
    let location: CourseIndexLocation
    let path: String
}

struct CourseIndexLocation: Codable, Equatable {
    let coordinate: CourseCoordinate
    let city: String
    let state: String
    let country: String
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpotGolfTests/CourseTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add Shared/Models/Course.swift SpotGolfTests/CourseTests.swift
git commit -m "feat: add Course data models for CourseData JSON format"
```

---

### Task 2: CourseService — Fetching and Caching

Create a service that fetches the index and course JSON from GitHub, with GZIP caching (5MB cap) and version-based index refresh.

**Files:**
- Create: `Shared/Services/CourseService.swift`
- Test: `SpotGolfTests/CourseServiceTests.swift`

**Step 1: Write the failing test**

```swift
// SpotGolfTests/CourseServiceTests.swift
import XCTest
@testable import SpotGolf

final class CourseServiceTests: XCTestCase {

    var service: CourseService!
    var cacheDir: URL!

    override func setUp() {
        super.setUp()
        cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CourseServiceTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        service = CourseService(cacheDirectory: cacheDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cacheDir)
        super.tearDown()
    }

    func testParseIndexVersion() {
        XCTAssertEqual(CourseService.parseVersion("42\n"), 42)
        XCTAssertEqual(CourseService.parseVersion("1"), 1)
        XCTAssertNil(CourseService.parseVersion("abc"))
        XCTAssertNil(CourseService.parseVersion(""))
    }

    func testCacheAndLoadCourseData() throws {
        let json = """
        {
          "id": "TEST-ID",
          "name": "Test Course",
          "clubName": "Test Club",
          "location": {
            "address": "123 Main",
            "city": "Denver",
            "coordinate": { "latitude": 39.0, "longitude": -105.0 },
            "country": "US",
            "state": "CO"
          },
          "subCourses": []
        }
        """.data(using: .utf8)!

        try service.cacheCourseData(json, forPath: "US/CO/Denver/Test-Course.json")

        let loaded = try service.loadCachedCourse(path: "US/CO/Denver/Test-Course.json")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, "TEST-ID")
    }

    func testCacheSizeEnforcement() throws {
        // Create data slightly under 5MB to test cache works
        let smallData = Data(count: 1024) // 1KB
        let path = "US/CO/Denver/Small.json"
        let validJSON = """
        {"id":"S","name":"S","clubName":"S","location":{"address":"x","city":"x","coordinate":{"latitude":0,"longitude":0},"country":"x","state":"x"},"subCourses":[]}
        """.data(using: .utf8)!
        try service.cacheCourseData(validJSON, forPath: path)
        XCTAssertTrue(service.cacheSizeBytes() < CourseService.maxCacheBytes)
    }

    func testCacheIndexAndLoad() throws {
        let entries = [
            CourseIndexEntry(
                name: "Test",
                clubName: "Test Club",
                location: CourseIndexLocation(
                    coordinate: CourseCoordinate(latitude: 39.0, longitude: -105.0),
                    city: "Denver",
                    state: "CO",
                    country: "US"
                ),
                path: "US/CO/Denver/Test.json"
            )
        ]
        let data = try JSONEncoder().encode(entries)
        try service.cacheIndex(data: data, version: 5)

        let loaded = try service.loadCachedIndex()
        XCTAssertEqual(loaded?.count, 1)
        XCTAssertEqual(loaded?[0].name, "Test")
        XCTAssertEqual(service.cachedIndexVersion(), 5)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpotGolfTests/CourseServiceTests 2>&1 | tail -20`
Expected: FAIL — CourseService type not found

**Step 3: Write minimal implementation**

```swift
// Shared/Services/CourseService.swift
import Foundation
import Compression

@MainActor
class CourseService: ObservableObject {
    static let maxCacheBytes = 5 * 1024 * 1024 // 5MB

    private static let baseRawURL = "https://raw.githubusercontent.com/SpotGolf/CourseData/refs/heads/main/"
    private static let indexVersionURL = baseRawURL + "index.version"
    private static let indexURL = baseRawURL + "index.json"

    @Published var index: [CourseIndexEntry] = []

    private let cacheDirectory: URL

    init(cacheDirectory: URL? = nil) {
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.cacheDirectory = docs.appendingPathComponent("CourseCache")
        }
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Index

    /// Fetch index from network, using version check to avoid unnecessary downloads.
    func refreshIndex() async {
        do {
            // Check remote version
            let remoteVersion = try await fetchIndexVersion()
            let localVersion = cachedIndexVersion()

            if let localVersion, localVersion >= remoteVersion,
               let cached = try loadCachedIndex() {
                index = cached
                return
            }

            // Download fresh index
            let (data, _) = try await URLSession.shared.data(from: URL(string: Self.indexURL)!)
            try cacheIndex(data: data, version: remoteVersion)
            index = try JSONDecoder().decode([CourseIndexEntry].self, from: data)
        } catch {
            // Fall back to cached index
            if let cached = try? loadCachedIndex() {
                index = cached
            }
            print("[CourseService] Index refresh failed: \(error)")
        }
    }

    private func fetchIndexVersion() async throws -> Int {
        let (data, _) = try await URLSession.shared.data(from: URL(string: Self.indexVersionURL)!)
        guard let str = String(data: data, encoding: .utf8),
              let version = Self.parseVersion(str) else {
            throw CourseServiceError.invalidVersion
        }
        return version
    }

    static func parseVersion(_ string: String) -> Int? {
        Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Course Fetch

    /// Fetch a course by its index path. Always downloads if online; falls back to cache.
    func fetchCourse(path: String) async throws -> Course {
        let urlString = Self.baseRawURL + path
        guard let url = URL(string: urlString) else {
            throw CourseServiceError.invalidURL
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let course = try JSONDecoder().decode(Course.self, from: data)
            try? cacheCourseData(data, forPath: path)
            return course
        } catch {
            // Fall back to cache
            if let cached = try? loadCachedCourse(path: path) {
                return cached
            }
            throw error
        }
    }

    // MARK: - Cache: Index

    func cacheIndex(data: Data, version: Int) throws {
        let indexFile = cacheDirectory.appendingPathComponent("index.json.gz")
        let versionFile = cacheDirectory.appendingPathComponent("index.version")
        try compressAndWrite(data, to: indexFile)
        try "\(version)".write(to: versionFile, atomically: true, encoding: .utf8)
    }

    func loadCachedIndex() throws -> [CourseIndexEntry]? {
        let indexFile = cacheDirectory.appendingPathComponent("index.json.gz")
        guard FileManager.default.fileExists(atPath: indexFile.path) else { return nil }
        let data = try decompressFile(at: indexFile)
        return try JSONDecoder().decode([CourseIndexEntry].self, from: data)
    }

    func cachedIndexVersion() -> Int? {
        let versionFile = cacheDirectory.appendingPathComponent("index.version")
        guard let str = try? String(contentsOf: versionFile, encoding: .utf8) else { return nil }
        return Self.parseVersion(str)
    }

    // MARK: - Cache: Course Data

    func cacheCourseData(_ data: Data, forPath path: String) throws {
        let cacheFile = courseCacheFile(for: path)
        let dir = cacheFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try compressAndWrite(data, to: cacheFile)
        enforeCacheLimit()
    }

    func loadCachedCourse(path: String) throws -> Course? {
        let cacheFile = courseCacheFile(for: path)
        guard FileManager.default.fileExists(atPath: cacheFile.path) else { return nil }
        let data = try decompressFile(at: cacheFile)
        return try JSONDecoder().decode(Course.self, from: data)
    }

    private func courseCacheFile(for path: String) -> URL {
        // Replace .json with .json.gz and nest under courses/
        let gzPath = path.hasSuffix(".json") ? path.replacingOccurrences(of: ".json", with: ".json.gz") : path + ".gz"
        return cacheDirectory.appendingPathComponent("courses").appendingPathComponent(gzPath)
    }

    // MARK: - Cache Size

    func cacheSizeBytes() -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += size
            }
        }
        return total
    }

    private func enforeCacheLimit() {
        guard cacheSizeBytes() > Self.maxCacheBytes else { return }
        let coursesDir = cacheDirectory.appendingPathComponent("courses")
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: coursesDir, includingPropertiesForKeys: [.contentAccessDateKey, .fileSizeKey]) else { return }

        var files: [(url: URL, date: Date)] = []
        for case let url as URL in enumerator {
            if let date = try? url.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate {
                files.append((url, date))
            }
        }
        // Remove oldest first
        files.sort { $0.date < $1.date }
        for file in files {
            guard cacheSizeBytes() > Self.maxCacheBytes else { break }
            try? fm.removeItem(at: file.url)
        }
    }

    // MARK: - GZIP Compression

    private func compressAndWrite(_ data: Data, to url: URL) throws {
        let compressed = try compress(data)
        try compressed.write(to: url)
    }

    private func compress(_ data: Data) throws -> Data {
        var result = Data()
        let pageSize = 65536
        var compressedBytes = [UInt8](repeating: 0, count: pageSize)

        let status = data.withUnsafeBytes { srcPointer -> compression_status in
            guard let srcBase = srcPointer.baseAddress else { return COMPRESSION_STATUS_ERROR }
            let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
            defer { stream.deallocate() }

            var s = compression_stream(
                dst_ptr: UnsafeMutablePointer<UInt8>(mutating: compressedBytes),
                dst_size: pageSize,
                src_ptr: srcBase.assumingMemoryBound(to: UInt8.self),
                src_size: data.count,
                state: nil
            )

            var initStatus = compression_stream_init(&s, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB)
            guard initStatus == COMPRESSION_STATUS_OK else { return initStatus }
            defer { compression_stream_destroy(&s) }

            s.dst_ptr = UnsafeMutablePointer<UInt8>(mutating: compressedBytes)
            s.dst_size = pageSize

            while true {
                let status = compression_stream_process(&s, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                if status == COMPRESSION_STATUS_OK {
                    result.append(compressedBytes, count: pageSize - s.dst_size)
                    s.dst_ptr = UnsafeMutablePointer<UInt8>(mutating: compressedBytes)
                    s.dst_size = pageSize
                } else if status == COMPRESSION_STATUS_END {
                    result.append(compressedBytes, count: pageSize - s.dst_size)
                    return status
                } else {
                    return status
                }
            }
        }

        guard status == COMPRESSION_STATUS_END else {
            throw CourseServiceError.compressionFailed
        }
        return result
    }

    private func decompressFile(at url: URL) throws -> Data {
        let compressed = try Data(contentsOf: url)
        return try decompress(compressed)
    }

    private func decompress(_ data: Data) throws -> Data {
        var result = Data()
        let pageSize = 65536
        var decompressedBytes = [UInt8](repeating: 0, count: pageSize)

        let status = data.withUnsafeBytes { srcPointer -> compression_status in
            guard let srcBase = srcPointer.baseAddress else { return COMPRESSION_STATUS_ERROR }
            var s = compression_stream(
                dst_ptr: UnsafeMutablePointer<UInt8>(mutating: decompressedBytes),
                dst_size: pageSize,
                src_ptr: srcBase.assumingMemoryBound(to: UInt8.self),
                src_size: data.count,
                state: nil
            )

            var initStatus = compression_stream_init(&s, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
            guard initStatus == COMPRESSION_STATUS_OK else { return initStatus }
            defer { compression_stream_destroy(&s) }

            s.dst_ptr = UnsafeMutablePointer<UInt8>(mutating: decompressedBytes)
            s.dst_size = pageSize

            while true {
                let status = compression_stream_process(&s, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                if status == COMPRESSION_STATUS_OK {
                    result.append(decompressedBytes, count: pageSize - s.dst_size)
                    s.dst_ptr = UnsafeMutablePointer<UInt8>(mutating: decompressedBytes)
                    s.dst_size = pageSize
                } else if status == COMPRESSION_STATUS_END {
                    result.append(decompressedBytes, count: pageSize - s.dst_size)
                    return status
                } else {
                    return status
                }
            }
        }

        guard status == COMPRESSION_STATUS_END else {
            throw CourseServiceError.decompressionFailed
        }
        return result
    }
}

enum CourseServiceError: Error {
    case invalidVersion
    case invalidURL
    case compressionFailed
    case decompressionFailed
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpotGolfTests/CourseServiceTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add Shared/Services/CourseService.swift SpotGolfTests/CourseServiceTests.swift
git commit -m "feat: add CourseService for fetching and caching course data"
```

---

### Task 3: Nearby and Search Logic

Add methods to filter the index by proximity (10 miles) and by name search.

**Files:**
- Modify: `Shared/Services/CourseService.swift`
- Test: `SpotGolfTests/CourseServiceTests.swift`

**Step 1: Write the failing test**

Add to `CourseServiceTests.swift`:

```swift
func testNearbyCourses() {
    let entries = [
        CourseIndexEntry(name: "Close Course", clubName: "Close", location: CourseIndexLocation(
            coordinate: CourseCoordinate(latitude: 39.956, longitude: -105.040),
            city: "Broomfield", state: "CO", country: "US"
        ), path: "close.json"),
        CourseIndexEntry(name: "Far Course", clubName: "Far", location: CourseIndexLocation(
            coordinate: CourseCoordinate(latitude: 40.5, longitude: -105.0),
            city: "FarCity", state: "CO", country: "US"
        ), path: "far.json"),
    ]
    service.index = entries

    let userLocation = CLLocation(latitude: 39.956, longitude: -105.040)
    let nearby = service.nearbyCourses(from: userLocation)

    XCTAssertEqual(nearby.count, 1)
    XCTAssertEqual(nearby[0].entry.name, "Close Course")
}

func testNearbyCourseSortedByDistance() {
    let entries = [
        CourseIndexEntry(name: "Farther", clubName: "F", location: CourseIndexLocation(
            coordinate: CourseCoordinate(latitude: 39.97, longitude: -105.040),
            city: "A", state: "CO", country: "US"
        ), path: "a.json"),
        CourseIndexEntry(name: "Closer", clubName: "C", location: CourseIndexLocation(
            coordinate: CourseCoordinate(latitude: 39.957, longitude: -105.040),
            city: "B", state: "CO", country: "US"
        ), path: "b.json"),
    ]
    service.index = entries

    let userLocation = CLLocation(latitude: 39.956, longitude: -105.040)
    let nearby = service.nearbyCourses(from: userLocation)

    XCTAssertEqual(nearby.count, 2)
    XCTAssertEqual(nearby[0].entry.name, "Closer")
    XCTAssertEqual(nearby[1].entry.name, "Farther")
}

func testSearchCoursesByName() {
    let entries = [
        CourseIndexEntry(name: "Broadlands Golf Course", clubName: "Broadlands", location: CourseIndexLocation(
            coordinate: CourseCoordinate(latitude: 39.0, longitude: -105.0),
            city: "Broomfield", state: "CO", country: "US"
        ), path: "broadlands.json"),
        CourseIndexEntry(name: "Arrowhead Golf Club", clubName: "Arrowhead", location: CourseIndexLocation(
            coordinate: CourseCoordinate(latitude: 39.0, longitude: -105.0),
            city: "Littleton", state: "CO", country: "US"
        ), path: "arrowhead.json"),
    ]
    service.index = entries

    let results = service.searchCourses(query: "broad")
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results[0].name, "Broadlands Golf Course")
}

func testSearchCoursesCaseInsensitive() {
    let entries = [
        CourseIndexEntry(name: "Broadlands Golf Course", clubName: "Broadlands", location: CourseIndexLocation(
            coordinate: CourseCoordinate(latitude: 39.0, longitude: -105.0),
            city: "Broomfield", state: "CO", country: "US"
        ), path: "broadlands.json"),
    ]
    service.index = entries

    let results = service.searchCourses(query: "BROAD")
    XCTAssertEqual(results.count, 1)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpotGolfTests/CourseServiceTests 2>&1 | tail -20`
Expected: FAIL — nearbyCourses/searchCourses not found

**Step 3: Write minimal implementation**

Add to `CourseService.swift`:

```swift
struct NearbyResult {
    let entry: CourseIndexEntry
    let distanceMiles: Double
}

// In CourseService:
private static let tenMilesInMeters: Double = 16093.44

func nearbyCourses(from location: CLLocation) -> [NearbyResult] {
    index.compactMap { entry in
        let courseLocation = entry.location.coordinate.clLocation
        let distance = location.distance(from: courseLocation)
        guard distance <= Self.tenMilesInMeters else { return nil }
        return NearbyResult(entry: entry, distanceMiles: distance / 1609.344)
    }
    .sorted { $0.distanceMiles < $1.distanceMiles }
}

func searchCourses(query: String) -> [CourseIndexEntry] {
    guard !query.isEmpty else { return [] }
    let lowered = query.lowercased()
    return index.filter { entry in
        entry.name.lowercased().contains(lowered) ||
        entry.clubName.lowercased().contains(lowered)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpotGolfTests/CourseServiceTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add Shared/Services/CourseService.swift SpotGolfTests/CourseServiceTests.swift
git commit -m "feat: add nearby course search (10mi) and name search to CourseService"
```

---

### Task 4: Attach Course Data to Round

Add course data to the `Round` model so a round can optionally reference a course and selected sub-courses.

**Files:**
- Modify: `Shared/Models/Round.swift`
- Test: `SpotGolfTests/RoundTests.swift`

**Step 1: Write the failing test**

Add to `RoundTests.swift`:

```swift
func testRoundWithCourseData() {
    let subCourse = SubCourse(name: "Front", holes: [
        CourseHole(id: "H1", number: 1, par: 4, maleHandicap: nil, femaleHandicap: nil,
                   green: CourseGreen(
                       front: CourseCoordinate(latitude: 39.0, longitude: -105.0),
                       middle: CourseCoordinate(latitude: 39.001, longitude: -105.0),
                       back: CourseCoordinate(latitude: 39.002, longitude: -105.0)
                   ),
                   tees: [:], yardages: [:], features: [])
    ])

    let selection = CourseSelection(
        course: Course(id: "C1", name: "Test", clubName: "Test Club",
                       location: CourseLocation(address: nil, city: "Denver",
                                                coordinate: CourseCoordinate(latitude: 39.0, longitude: -105.0),
                                                country: "US", state: "CO"),
                       subCourses: [subCourse]),
        selectedSubCourseIndices: [0]
    )

    var round = Round(courseSelection: selection)
    XCTAssertNotNil(round.courseSelection)
    XCTAssertEqual(round.courseSelection?.selectedSubCourseIndices, [0])
}

func testRoundWithoutCourseData() {
    let round = Round()
    XCTAssertNil(round.courseSelection)
}

func testRoundCourseSelectionEncodeDecode() throws {
    let subCourse = SubCourse(name: "Front", holes: [
        CourseHole(id: "H1", number: 1, par: 4, maleHandicap: nil, femaleHandicap: nil,
                   green: CourseGreen(
                       front: CourseCoordinate(latitude: 39.0, longitude: -105.0),
                       middle: CourseCoordinate(latitude: 39.001, longitude: -105.0),
                       back: CourseCoordinate(latitude: 39.002, longitude: -105.0)
                   ),
                   tees: [:], yardages: [:], features: [])
    ])

    let selection = CourseSelection(
        course: Course(id: "C1", name: "Test", clubName: "Test Club",
                       location: CourseLocation(address: nil, city: "Denver",
                                                coordinate: CourseCoordinate(latitude: 39.0, longitude: -105.0),
                                                country: "US", state: "CO"),
                       subCourses: [subCourse]),
        selectedSubCourseIndices: [0]
    )

    var round = Round(courseSelection: selection)
    let data = try JSONEncoder().encode(round)
    let decoded = try JSONDecoder().decode(Round.self, from: data)
    XCTAssertEqual(decoded.courseSelection?.course.id, "C1")
    XCTAssertEqual(decoded.courseSelection?.selectedSubCourseIndices, [0])
}

func testCurrentCourseHole() {
    let holes = [
        CourseHole(id: "H1", number: 1, par: 4, maleHandicap: nil, femaleHandicap: nil,
                   green: CourseGreen(
                       front: CourseCoordinate(latitude: 39.0, longitude: -105.0),
                       middle: CourseCoordinate(latitude: 39.001, longitude: -105.0),
                       back: CourseCoordinate(latitude: 39.002, longitude: -105.0)
                   ),
                   tees: [:], yardages: [:], features: []),
        CourseHole(id: "H2", number: 2, par: 3, maleHandicap: nil, femaleHandicap: nil,
                   green: CourseGreen(
                       front: CourseCoordinate(latitude: 39.01, longitude: -105.0),
                       middle: CourseCoordinate(latitude: 39.011, longitude: -105.0),
                       back: CourseCoordinate(latitude: 39.012, longitude: -105.0)
                   ),
                   tees: [:], yardages: [:], features: [])
    ]

    let selection = CourseSelection(
        course: Course(id: "C1", name: "Test", clubName: "Test Club",
                       location: CourseLocation(address: nil, city: "Denver",
                                                coordinate: CourseCoordinate(latitude: 39.0, longitude: -105.0),
                                                country: "US", state: "CO"),
                       subCourses: [SubCourse(name: "Front", holes: holes)]),
        selectedSubCourseIndices: [0]
    )

    var round = Round(courseSelection: selection)
    XCTAssertEqual(round.currentCourseHole?.number, 1)
    round.nextHole()
    XCTAssertEqual(round.currentCourseHole?.number, 2)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpotGolfTests/RoundTests 2>&1 | tail -20`
Expected: FAIL — CourseSelection not found

**Step 3: Write minimal implementation**

Add `CourseSelection` to `Shared/Models/Course.swift`:

```swift
struct CourseSelection: Codable, Equatable {
    let course: Course
    let selectedSubCourseIndices: [Int]

    /// All holes in play order across selected sub-courses.
    var orderedHoles: [CourseHole] {
        selectedSubCourseIndices.flatMap { index in
            guard index < course.subCourses.count else { return [CourseHole]() }
            return course.subCourses[index].holes
        }
    }
}
```

Modify `Round.swift` — add `courseSelection` property:

- Add `var courseSelection: CourseSelection?` to the struct
- Update `init` to accept optional `courseSelection`
- Add `currentCourseHole` computed property
- Update Codable to encode/decode `courseSelection`
- Update `==` to include `courseSelection`

```swift
// Add to Round struct:
var courseSelection: CourseSelection?

// Update init:
init(id: UUID = UUID(), date: Date = Date(), holes: [Hole] = [Hole()],
     currentHoleIndex: Int = 0, isActive: Bool = true, courseSelection: CourseSelection? = nil) {
    self.id = id
    self.date = date
    self.holes = holes
    self.currentHoleIndex = currentHoleIndex
    self.isActive = isActive
    self.courseSelection = courseSelection
}

// Add computed property:
var currentCourseHole: CourseHole? {
    guard let selection = courseSelection else { return nil }
    let orderedHoles = selection.orderedHoles
    guard currentHoleIndex < orderedHoles.count else { return nil }
    return orderedHoles[currentHoleIndex]
}

// Update == :
static func == (lhs: Round, rhs: Round) -> Bool {
    lhs.id == rhs.id &&
    lhs.date == rhs.date &&
    lhs.holes == rhs.holes &&
    lhs.currentHoleIndex == rhs.currentHoleIndex &&
    lhs.isActive == rhs.isActive &&
    lhs.courseSelection == rhs.courseSelection
}

// Update CodingKeys:
private enum CodingKeys: String, CodingKey {
    case id, date, holes, currentHoleIndex, isActive, courseSelection
    case marks // legacy key
}

// Update init(from decoder:) — add after isActive decode:
courseSelection = try container.decodeIfPresent(CourseSelection.self, forKey: .courseSelection)

// Update encode(to:) — add:
try container.encodeIfPresent(courseSelection, forKey: .courseSelection)
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpotGolfTests/RoundTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add Shared/Models/Round.swift Shared/Models/Course.swift SpotGolfTests/RoundTests.swift
git commit -m "feat: attach optional CourseSelection to Round model"
```

---

### Task 5: Distance Calculations for Course Features

Add methods to calculate distances to green and features ahead of the player.

**Files:**
- Modify: `Shared/Utilities/DistanceCalculator.swift`
- Test: `SpotGolfTests/DistanceCalculatorTests.swift`

**Step 1: Write the failing test**

Add to `DistanceCalculatorTests.swift`:

```swift
func testDistancesToGreen() {
    let green = CourseGreen(
        front: CourseCoordinate(latitude: 39.9550, longitude: -105.0456),
        middle: CourseCoordinate(latitude: 39.9550, longitude: -105.0458),
        back: CourseCoordinate(latitude: 39.9549, longitude: -105.0460)
    )
    let userLocation = CLLocation(latitude: 39.9540, longitude: -105.0430)

    let distances = DistanceCalculator.greenDistances(from: userLocation, green: green)

    XCTAssertGreaterThan(distances.front, 0)
    XCTAssertGreaterThan(distances.middle, distances.front)
    XCTAssertGreaterThan(distances.back, distances.middle)
}

func testFeaturesAhead() {
    let green = CourseGreen(
        front: CourseCoordinate(latitude: 39.960, longitude: -105.040),
        middle: CourseCoordinate(latitude: 39.961, longitude: -105.040),
        back: CourseCoordinate(latitude: 39.962, longitude: -105.040)
    )
    let bunkerAhead = CourseFeature(
        id: "B1", type: .bunker,
        front: CourseCoordinate(latitude: 39.958, longitude: -105.040),
        back: CourseCoordinate(latitude: 39.959, longitude: -105.040)
    )
    let bunkerBehind = CourseFeature(
        id: "B2", type: .bunker,
        front: CourseCoordinate(latitude: 39.950, longitude: -105.040),
        back: CourseCoordinate(latitude: 39.951, longitude: -105.040)
    )
    let userLocation = CLLocation(latitude: 39.955, longitude: -105.040)

    let ahead = DistanceCalculator.featuresAhead(
        from: userLocation, features: [bunkerAhead, bunkerBehind], green: green
    )

    XCTAssertEqual(ahead.count, 1)
    XCTAssertEqual(ahead[0].feature.id, "B1")
    XCTAssertGreaterThan(ahead[0].distanceYards, 0)
}

func testFeaturesAheadSortedByDistance() {
    let green = CourseGreen(
        front: CourseCoordinate(latitude: 39.970, longitude: -105.040),
        middle: CourseCoordinate(latitude: 39.971, longitude: -105.040),
        back: CourseCoordinate(latitude: 39.972, longitude: -105.040)
    )
    let nearBunker = CourseFeature(
        id: "B1", type: .bunker,
        front: CourseCoordinate(latitude: 39.956, longitude: -105.040),
        back: CourseCoordinate(latitude: 39.957, longitude: -105.040)
    )
    let farBunker = CourseFeature(
        id: "B2", type: .bunker,
        front: CourseCoordinate(latitude: 39.965, longitude: -105.040),
        back: CourseCoordinate(latitude: 39.966, longitude: -105.040)
    )
    let userLocation = CLLocation(latitude: 39.955, longitude: -105.040)

    let ahead = DistanceCalculator.featuresAhead(
        from: userLocation, features: [farBunker, nearBunker], green: green
    )

    XCTAssertEqual(ahead.count, 2)
    XCTAssertEqual(ahead[0].feature.id, "B1") // closer first
    XCTAssertEqual(ahead[1].feature.id, "B2")
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpotGolfTests/DistanceCalculatorTests 2>&1 | tail -20`
Expected: FAIL — greenDistances/featuresAhead not found

**Step 3: Write minimal implementation**

Add to `DistanceCalculator.swift`:

```swift
struct GreenDistances {
    let front: Int
    let middle: Int
    let back: Int
}

struct FeatureDistance {
    let feature: CourseFeature
    let distanceYards: Int
}

// In DistanceCalculator enum:
static func greenDistances(from location: CLLocation, green: CourseGreen) -> GreenDistances {
    GreenDistances(
        front: Int(yards(from: location, to: green.front.clLocation)),
        middle: Int(yards(from: location, to: green.middle.clLocation)),
        back: Int(yards(from: location, to: green.back.clLocation))
    )
}

/// Returns features that are ahead of the user (between user and green), sorted by distance.
static func featuresAhead(from location: CLLocation, features: [CourseFeature], green: CourseGreen) -> [FeatureDistance] {
    let distToGreen = location.distance(from: green.middle.clLocation)

    return features.compactMap { feature in
        let featureLocation = feature.middle
        let distToFeature = location.distance(from: featureLocation)
        let featureToGreen = featureLocation.distance(from: green.middle.clLocation)

        // Feature is "ahead" if it's closer to the green than we are
        // and closer to us than the green is
        guard featureToGreen < distToGreen && distToFeature < distToGreen else { return nil }

        return FeatureDistance(
            feature: feature,
            distanceYards: Int(distToFeature * metersToYards)
        )
    }
    .sorted { $0.distanceYards < $1.distanceYards }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpotGolfTests/DistanceCalculatorTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add Shared/Utilities/DistanceCalculator.swift SpotGolfTests/DistanceCalculatorTests.swift
git commit -m "feat: add green and feature distance calculations"
```

---

### Task 6: Auto-Advance Holes via GPS

Create a `HoleAdvancer` that monitors location and auto-advances to the correct hole when near a tee box.

**Files:**
- Create: `Shared/Services/HoleAdvancer.swift`
- Test: `SpotGolfTests/HoleAdvancerTests.swift`

**Step 1: Write the failing test**

```swift
// SpotGolfTests/HoleAdvancerTests.swift
import XCTest
import CoreLocation
@testable import SpotGolf

final class HoleAdvancerTests: XCTestCase {

    func testDetectsCorrectHole() {
        let holes = makeTestHoles()
        let selection = makeSelection(holes: holes)

        // User is near hole 2 tee
        let location = CLLocation(latitude: 39.960, longitude: -105.040)
        let detected = HoleAdvancer.detectHole(location: location, courseSelection: selection)

        XCTAssertEqual(detected, 1) // 0-based index for hole 2
    }

    func testReturnsNilWhenNotNearAnyTee() {
        let holes = makeTestHoles()
        let selection = makeSelection(holes: holes)

        // User is far from any tee
        let location = CLLocation(latitude: 40.0, longitude: -106.0)
        let detected = HoleAdvancer.detectHole(location: location, courseSelection: selection)

        XCTAssertNil(detected)
    }

    func testManualOverridePausesAutoAdvance() {
        var advancer = HoleAdvancer()
        advancer.pause()
        XCTAssertTrue(advancer.isPaused)
    }

    func testResumeReEnablesAutoAdvance() {
        var advancer = HoleAdvancer()
        advancer.pause()
        advancer.resume()
        XCTAssertFalse(advancer.isPaused)
    }

    // MARK: - Helpers

    private func makeTestHoles() -> [CourseHole] {
        [
            CourseHole(id: "H1", number: 1, par: 4, maleHandicap: nil, femaleHandicap: nil,
                       green: CourseGreen(
                           front: CourseCoordinate(latitude: 39.955, longitude: -105.045),
                           middle: CourseCoordinate(latitude: 39.955, longitude: -105.046),
                           back: CourseCoordinate(latitude: 39.955, longitude: -105.047)
                       ),
                       tees: ["Blue": CourseCoordinate(latitude: 39.950, longitude: -105.040)],
                       yardages: [:], features: []),
            CourseHole(id: "H2", number: 2, par: 3, maleHandicap: nil, femaleHandicap: nil,
                       green: CourseGreen(
                           front: CourseCoordinate(latitude: 39.965, longitude: -105.045),
                           middle: CourseCoordinate(latitude: 39.965, longitude: -105.046),
                           back: CourseCoordinate(latitude: 39.965, longitude: -105.047)
                       ),
                       tees: ["Blue": CourseCoordinate(latitude: 39.960, longitude: -105.040)],
                       yardages: [:], features: []),
        ]
    }

    private func makeSelection(holes: [CourseHole]) -> CourseSelection {
        CourseSelection(
            course: Course(id: "C1", name: "Test", clubName: "Test",
                           location: CourseLocation(address: nil, city: "Denver",
                                                    coordinate: CourseCoordinate(latitude: 39.0, longitude: -105.0),
                                                    country: "US", state: "CO"),
                           subCourses: [SubCourse(name: "Front", holes: holes)]),
            selectedSubCourseIndices: [0]
        )
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpotGolfTests/HoleAdvancerTests 2>&1 | tail -20`
Expected: FAIL — HoleAdvancer not found

**Step 3: Write minimal implementation**

```swift
// Shared/Services/HoleAdvancer.swift
import Foundation
import CoreLocation

struct HoleAdvancer {
    private(set) var isPaused = false

    /// Maximum distance in meters from a tee box to trigger auto-advance.
    static let teeProximityMeters: Double = 30.0

    mutating func pause() {
        isPaused = true
    }

    mutating func resume() {
        isPaused = false
    }

    /// Detects which hole (0-based index into orderedHoles) the user is near,
    /// based on proximity to tee boxes. Returns nil if not near any tee.
    static func detectHole(location: CLLocation, courseSelection: CourseSelection) -> Int? {
        let orderedHoles = courseSelection.orderedHoles

        var closestIndex: Int?
        var closestDistance = Double.greatestFiniteMagnitude

        for (index, hole) in orderedHoles.enumerated() {
            for (_, teeCoord) in hole.tees {
                let distance = location.distance(from: teeCoord.clLocation)
                if distance < teeProximityMeters && distance < closestDistance {
                    closestDistance = distance
                    closestIndex = index
                }
            }
        }

        return closestIndex
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpotGolfTests/HoleAdvancerTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add Shared/Services/HoleAdvancer.swift SpotGolfTests/HoleAdvancerTests.swift
git commit -m "feat: add HoleAdvancer for GPS-based auto-advance"
```

---

### Task 7: Sync Course Selection to watchOS

Add a new `SyncMessage` case so course selection syncs from iOS to watchOS.

**Files:**
- Modify: `Shared/Models/SyncMessage.swift`
- Modify: `Shared/Services/SyncService.swift`
- Modify: `Shared/Services/RoundStore.swift`
- Test: `SpotGolfTests/SyncServiceTests.swift`

**Step 1: Write the failing test**

Add to `SyncServiceTests.swift`:

```swift
func testSendCourseSelection() throws {
    let selection = CourseSelection(
        course: Course(id: "C1", name: "Test", clubName: "Test",
                       location: CourseLocation(address: nil, city: "Denver",
                                                coordinate: CourseCoordinate(latitude: 39.0, longitude: -105.0),
                                                country: "US", state: "CO"),
                       subCourses: []),
        selectedSubCourseIndices: [0, 1]
    )
    let roundID = UUID()

    // Verify message can be constructed and handled
    let message = SyncMessage.setCourse(selection, roundID)

    // Encode selection to verify it round-trips
    let data = try JSONEncoder().encode(selection)
    let decoded = try JSONDecoder().decode(CourseSelection.self, from: data)
    XCTAssertEqual(decoded.course.id, "C1")
    XCTAssertEqual(decoded.selectedSubCourseIndices, [0, 1])
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpotGolfTests/SyncServiceTests 2>&1 | tail -20`
Expected: FAIL — setCourse not found on SyncMessage

**Step 3: Write minimal implementation**

Update `SyncMessage.swift`:

```swift
enum SyncMessage {
    case startRound(UUID, Date)
    case endRound(UUID)
    case addMark(BallMark, UUID)
    case nextHole(UUID)
    case previousHole(UUID)
    case setCourse(CourseSelection, UUID) // selection + roundID
}
```

Update `SyncService.swift` `sendOnMain` — add case:

```swift
case .setCourse(let selection, let roundID):
    guard let data = try? JSONEncoder().encode(selection) else { return }
    payload = [
        "type": "setCourse",
        "roundId": roundID.uuidString,
        "courseSelection": data
    ]
```

Update `SyncService.swift` `handleMessage` — add case:

```swift
case "setCourse":
    guard let data = message["courseSelection"] as? Data,
          let idString = message["roundId"] as? String,
          let roundID = UUID(uuidString: idString),
          let selection = try? JSONDecoder().decode(CourseSelection.self, from: data) else { return }
    roundStore?.setCourse(selection, for: roundID, fromSync: true)
```

Update `RoundStore.swift` — add method:

```swift
func setCourse(_ selection: CourseSelection, for roundID: UUID? = nil, fromSync: Bool = false) {
    let predicate: (Round) -> Bool = if let roundID {
        { $0.id == roundID }
    } else {
        { $0.isActive }
    }
    if let index = rounds.firstIndex(where: predicate) {
        let id = rounds[index].id
        rounds[index].courseSelection = selection
        save()
        if !fromSync {
            onSyncEvent?(.setCourse(selection, id))
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpotGolfTests/SyncServiceTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add Shared/Models/SyncMessage.swift Shared/Services/SyncService.swift Shared/Services/RoundStore.swift SpotGolfTests/SyncServiceTests.swift
git commit -m "feat: sync course selection from iOS to watchOS"
```

---

### Task 8: Course Selection UI (iOS)

Build the course selection screen shown when tapping "New Round".

**Files:**
- Create: `SpotGolf/Views/CourseSelectionView.swift`
- Modify: `SpotGolf/Views/RoundListView.swift`
- Modify: `SpotGolf/SpotGolfApp.swift` (add CourseService as environment object)

**Step 1: Write the implementation**

Note: UI views are best tested via UI tests in Task 12. Build the views now.

```swift
// SpotGolf/Views/CourseSelectionView.swift
import SwiftUI
import CoreLocation

struct CourseSelectionView: View {
    @EnvironmentObject var courseService: CourseService
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var roundStore: RoundStore
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedEntry: CourseIndexEntry?
    @State private var loadedCourse: Course?
    @State private var selectedSubCourseIndices: [Int] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let course = loadedCourse {
                    subCourseSelectionView(course)
                } else {
                    courseListView
                }
            }
            .navigationTitle(loadedCourse != nil ? "Select Holes" : "Select Course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        roundStore.startRound()
                        dismiss()
                    }
                }
            }
            .task {
                await courseService.refreshIndex()
            }
        }
    }

    private var courseListView: some View {
        List {
            if !searchText.isEmpty {
                let results = courseService.searchCourses(query: searchText)
                if results.isEmpty {
                    Text("No courses found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results, id: \.path) { entry in
                        courseRow(entry: entry, distance: nil)
                    }
                }
            } else if let location = locationManager.lastLocation {
                let nearby = courseService.nearbyCourses(from: location)
                if nearby.isEmpty {
                    Section {
                        Text("No courses within 10 miles")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Nearby Courses") {
                        ForEach(nearby, id: \.entry.path) { result in
                            courseRow(entry: result.entry, distance: result.distanceMiles)
                        }
                    }
                }
            } else {
                Text("Locating...")
                    .foregroundStyle(.secondary)
            }

            if let error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search courses")
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
    }

    private func courseRow(entry: CourseIndexEntry, distance: Double?) -> some View {
        Button {
            Task { await selectCourse(entry) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                HStack {
                    Text("\(entry.location.city), \(entry.location.state)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let distance {
                        Spacer()
                        Text(String(format: "%.1f mi", distance))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func selectCourse(_ entry: CourseIndexEntry) async {
        isLoading = true
        error = nil
        do {
            let course = try await courseService.fetchCourse(path: entry.path)
            loadedCourse = course

            // Default sub-course selection
            if course.subCourses.count <= 1 {
                selectedSubCourseIndices = [0]
            } else {
                // Try to find Front/Back
                let frontIdx = course.subCourses.firstIndex { $0.name?.lowercased().contains("front") == true }
                let backIdx = course.subCourses.firstIndex { $0.name?.lowercased().contains("back") == true }
                if let f = frontIdx, let b = backIdx {
                    selectedSubCourseIndices = [f, b]
                } else {
                    selectedSubCourseIndices = Array(0..<min(2, course.subCourses.count))
                }
            }
        } catch {
            self.error = "Failed to load course: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func subCourseSelectionView(_ course: Course) -> some View {
        List {
            if course.subCourses.count > 1 {
                Section("Select sub-courses in play order") {
                    ForEach(Array(course.subCourses.enumerated()), id: \.offset) { index, sub in
                        let isSelected = selectedSubCourseIndices.contains(index)
                        let position = selectedSubCourseIndices.firstIndex(of: index)
                        Button {
                            if isSelected {
                                selectedSubCourseIndices.removeAll { $0 == index }
                            } else if selectedSubCourseIndices.count < 2 {
                                selectedSubCourseIndices.append(index)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(sub.name ?? "Course \(index + 1)")
                                        .foregroundStyle(.primary)
                                    Text("\(sub.holes.count) holes")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let position {
                                    Text("\(position + 1)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                        .frame(width: 24, height: 24)
                                        .background(Color.green)
                                        .clipShape(Circle())
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Button("Start Round") {
                    let selection = CourseSelection(
                        course: course,
                        selectedSubCourseIndices: selectedSubCourseIndices
                    )
                    roundStore.startRound()
                    roundStore.setCourse(selection)
                    dismiss()
                }
                .disabled(selectedSubCourseIndices.isEmpty)
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") {
                    loadedCourse = nil
                }
            }
        }
    }
}
```

Update `RoundListView.swift` — change the "New Round" button to show the course selection sheet:

```swift
// Add state:
@State private var showCourseSelection = false

// Change the "New Round" button action:
Button("New Round") {
    showCourseSelection = true
}

// Add sheet modifier to the List:
.sheet(isPresented: $showCourseSelection) {
    CourseSelectionView()
}
```

Update `SpotGolfApp.swift` — add `CourseService` as environment object:

```swift
@StateObject private var courseService = CourseService()

// Add to environment:
.environmentObject(courseService)
```

**Step 2: Build to verify compilation**

Run: `xcodebuild build -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SpotGolf/Views/CourseSelectionView.swift SpotGolf/Views/RoundListView.swift SpotGolf/SpotGolfApp.swift
git commit -m "feat: add course selection UI with nearby and search"
```

---

### Task 9: Distance Display Panel (iOS)

Add an always-visible distance card on the map view when course data is attached.

**Files:**
- Modify: `SpotGolf/Views/RoundMapView.swift`

**Step 1: Write the implementation**

Add a `distancePanel` view to `RoundMapView.swift`:

```swift
@ViewBuilder
private func distancePanel(_ round: Round) -> some View {
    if let courseHole = round.currentCourseHole,
       let location = locationManager.lastLocation {
        let greenDist = DistanceCalculator.greenDistances(from: location, green: courseHole.green)
        let features = DistanceCalculator.featuresAhead(
            from: location, features: courseHole.features, green: courseHole.green
        )

        VStack(alignment: .leading, spacing: 6) {
            // Par info
            Text("Par \(courseHole.par)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            // Green distances
            HStack(spacing: 16) {
                distanceLabel("Front", greenDist.front)
                distanceLabel("Mid", greenDist.middle)
                distanceLabel("Back", greenDist.back)
            }

            // Features ahead
            if !features.isEmpty {
                Divider()
                ForEach(features, id: \.feature.id) { fd in
                    HStack {
                        Image(systemName: fd.feature.type == .water ? "drop.fill" : "square.fill")
                            .font(.caption2)
                            .foregroundStyle(fd.feature.type == .water ? .blue : .yellow)
                        Text(fd.feature.type == .water ? "Water" : "Bunker")
                            .font(.caption)
                        Spacer()
                        Text("\(fd.distanceYards) yds")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
}

private func distanceLabel(_ label: String, _ yards: Int) -> some View {
    VStack(spacing: 2) {
        Text("\(yards)")
            .font(.title3)
            .fontWeight(.bold)
        Text(label)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
```

Update `overlayView` to include the distance panel:

```swift
private func overlayView(_ round: Round) -> some View {
    VStack {
        statsBar(round)
        distancePanel(round)
        Spacer()
        if round.isActive {
            buttonBar(round)
        }
    }
}
```

**Step 2: Build to verify compilation**

Run: `xcodebuild build -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SpotGolf/Views/RoundMapView.swift
git commit -m "feat: add always-visible distance panel on iOS map view"
```

---

### Task 10: Auto-Advance + Resume Round (iOS)

Integrate `HoleAdvancer` into `RoundMapView` to auto-advance holes and show "Resume round" button.

**Files:**
- Modify: `SpotGolf/Views/RoundMapView.swift`

**Step 1: Write the implementation**

Add state and logic to `RoundMapView.swift`:

```swift
// Add state:
@State private var holeAdvancer = HoleAdvancer()
@State private var detectedHoleIndex: Int?

// Add to onReceive(locationManager.$lastLocation):
// After existing followsUserLocation logic, add:
if let round, let selection = round.courseSelection, !holeAdvancer.isPaused, let location {
    if let detected = HoleAdvancer.detectHole(location: location, courseSelection: selection),
       detected != round.currentHoleIndex {
        detectedHoleIndex = detected
        // Auto-advance: set hole index directly
        roundStore.setHoleIndex(detected)
    }
}

// Modify prev/next hole buttons to pause auto-advance:
Button {
    holeAdvancer.pause()
    roundStore.previousHole()
} label: { ... }

Button {
    holeAdvancer.pause()
    roundStore.nextHole()
} label: { ... }

// Add "Resume round" button when paused:
if holeAdvancer.isPaused {
    Button("Resume round") {
        holeAdvancer.resume()
        if let round, let selection = round.courseSelection,
           let location = locationManager.lastLocation,
           let detected = HoleAdvancer.detectHole(location: location, courseSelection: selection) {
            roundStore.setHoleIndex(detected)
        }
    }
    .buttonStyle(.bordered)
    .tint(.blue)
}
```

Add `setHoleIndex` to `RoundStore.swift`:

```swift
func setHoleIndex(_ index: Int, roundID: UUID? = nil, fromSync: Bool = false) {
    let predicate: (Round) -> Bool = if let roundID {
        { $0.id == roundID }
    } else {
        { $0.isActive }
    }
    if let i = rounds.firstIndex(where: predicate) {
        // Ensure enough holes exist
        while rounds[i].holes.count <= index && rounds[i].holes.count < 18 {
            rounds[i].holes.append(Hole())
        }
        let clamped = min(index, rounds[i].holes.count - 1)
        guard clamped != rounds[i].currentHoleIndex else { return }
        rounds[i].currentHoleIndex = clamped
        save()
    }
}
```

**Step 2: Build to verify compilation**

Run: `xcodebuild build -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SpotGolf/Views/RoundMapView.swift Shared/Services/RoundStore.swift
git commit -m "feat: integrate auto-advance with Resume round button"
```

---

### Task 11: watchOS Swing Away with Distances and Dismiss

Update the watch "Swing away" screen to show distances and use a dismiss button instead of a timer.

**Files:**
- Modify: `SpotGolfWatch/Views/WatchRoundView.swift`

**Step 1: Write the implementation**

Replace the swing away display and remove the timer:

```swift
// Remove swingAwayTask state variable entirely.
// Keep showSwingAway state.

// Replace the showSwingAway view:
if showSwingAway {
    swingAwayView(round: roundStore.activeRound)
}

// New swing away view with distances and dismiss:
@ViewBuilder
private func swingAwayView(round: Round?) -> some View {
    ScrollView {
        VStack(spacing: 8) {
            Text("Swing away")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.green)

            if let round, let courseHole = round.currentCourseHole,
               let location = locationManager.lastLocation {
                let greenDist = DistanceCalculator.greenDistances(from: location, green: courseHole.green)

                Divider()

                // Green distances
                HStack(spacing: 12) {
                    VStack(spacing: 1) {
                        Text("\(greenDist.front)")
                            .font(.body).fontWeight(.bold)
                        Text("Front")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 1) {
                        Text("\(greenDist.middle)")
                            .font(.body).fontWeight(.bold)
                        Text("Mid")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 1) {
                        Text("\(greenDist.back)")
                            .font(.body).fontWeight(.bold)
                        Text("Back")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }

                // Features ahead
                let features = DistanceCalculator.featuresAhead(
                    from: location, features: courseHole.features, green: courseHole.green
                )
                if !features.isEmpty {
                    Divider()
                    ForEach(features, id: \.feature.id) { fd in
                        HStack {
                            Image(systemName: fd.feature.type == .water ? "drop.fill" : "square.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(fd.feature.type == .water ? .blue : .yellow)
                            Text(fd.feature.type == .water ? "Water" : "Bunker")
                                .font(.caption2)
                            Spacer()
                            Text("\(fd.distanceYards)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }

            Spacer()

            Button("Dismiss") {
                showSwingAway = false
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

// Update markBall() - remove timer, just show swing away:
private func markBall() {
    guard let location = locationManager.lastLocation else { return }
    let mark = BallMark(coordinate: location.coordinate)
    roundStore.addMark(mark)
    showSwingAway = true
}

// Remove onDisappear swingAwayTask cancel (no longer needed)
```

**Step 2: Build to verify compilation**

Run: `xcodebuild build -scheme SpotGolfWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SpotGolfWatch/Views/WatchRoundView.swift
git commit -m "feat: watchOS swing away with distances and dismiss button"
```

---

### Task 12: Update project.yml for CourseService dependency

Ensure `project.yml` doesn't need changes — `CourseService` is in `Shared/` which is already included in both targets. Verify the build.

**Step 1: Build both targets**

Run: `xcodebuild build -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Run: `xcodebuild build -scheme SpotGolfWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' 2>&1 | tail -10`
Expected: Both BUILD SUCCEEDED

**Step 2: Run all existing tests**

Run: `xcodebuild test -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`
Expected: All tests pass

**Step 3: Commit if any project.yml changes were needed**

---

### Task 13: Final Integration Test

Verify end-to-end: build both targets, run all unit tests, and manually verify the course selection flow compiles.

**Step 1: Run full test suite**

Run: `xcodebuild test -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: All tests pass

**Step 2: Verify clean build**

Run: `xcodebuild clean build -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Run: `xcodebuild clean build -scheme SpotGolfWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' 2>&1 | tail -10`
Expected: Both BUILD SUCCEEDED
