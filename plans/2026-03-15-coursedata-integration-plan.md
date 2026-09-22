# CourseData Package Integration — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SpotGolf's local course model types with the shared CourseData Swift package and update all code for the new polygon-based data format.

**Architecture:** Add CourseData as a Swift Package dependency. Delete `Course.swift`, extract `CourseIndexEntry` and `CourseSelection` into their own files, rename `Hole` to `RoundHole` to avoid the naming collision with `CourseData.Hole`, then update all services, utilities, views, and tests.

**Tech Stack:** Swift, SwiftUI, CourseData Swift Package, CoreLocation, WatchConnectivity

**Spec:** `plans/2026-03-15-coursedata-integration-design.md`

---

## Chunk 1: Foundation — Package Dependency, Model Extraction, and Rename

### Task 1: Add CourseData Swift Package dependency

**Files:**
- Modify: `SpotGolf.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add the package via `xcodebuild`**

The CourseData package must be added to the Xcode project. This is best done in Xcode:

1. Open `SpotGolf.xcodeproj` in Xcode
2. File → Add Package Dependencies
3. Enter URL: `https://github.com/SpotGolf/CourseData`
4. Set dependency rule to "Branch: main"
5. Add the `CourseData` library to both the `SpotGolf` (iOS) and `SpotGolfWatch Watch App` (watchOS) targets

Alternatively, add via the local path `../CourseData` for faster iteration during development.

- [ ] **Step 2: Verify the build still succeeds**

Run: `xcodebuild -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add SpotGolf.xcodeproj/project.pbxproj
git commit -m "Add CourseData Swift Package dependency"
```

---

### Task 2: Rename `Hole` to `RoundHole`

**Files:**
- Modify: `Shared/Models/Hole.swift`
- Modify: `Shared/Models/Round.swift`
- Modify: `Shared/Services/RoundStore.swift`
- Modify: `SpotGolf/Views/RoundMapView.swift`
- Modify: `SpotGolfTests/HoleTests.swift`
- Modify: `SpotGolfTests/RoundTests.swift`
- Modify: `SpotGolfTests/RoundStoreTests.swift`

- [ ] **Step 1: Rename the struct in `Shared/Models/Hole.swift`**

```swift
struct RoundHole: Identifiable, Codable, Equatable {
    let id: UUID
    var marks: [BallMark]

    init(id: UUID = UUID(), marks: [BallMark] = []) {
        self.id = id
        self.marks = marks
    }

    var strokeCount: Int {
        max(marks.count - 1, 0)
    }
}
```

- [ ] **Step 2: Update `Round.swift`**

Replace all references to `Hole` with `RoundHole`:
- `var holes: [Hole]` → `var holes: [RoundHole]`
- `Hole()` → `RoundHole()`
- `Hole(marks:)` → `RoundHole(marks:)`
- `[Hole].self` → `[RoundHole].self`

- [ ] **Step 3: Update `RoundStore.swift`**

Replace all references to `Hole` with `RoundHole`:
- `rounds[i].holes.append(Hole())` → `rounds[i].holes.append(RoundHole())`

- [ ] **Step 4: Update test files**

In `HoleTests.swift`, `RoundTests.swift`, and `RoundStoreTests.swift`:
- Replace all `Hole(` with `RoundHole(`
- Replace all `Hole()` with `RoundHole()`
- Replace `[Hole]` with `[RoundHole]`
- Replace `Hole.self` with `RoundHole.self`

- [ ] **Step 5: Build and run tests**

Run: `xcodebuild test -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Rename Hole to RoundHole to avoid CourseData naming conflict"
```

---

### Task 3: Delete `Course.swift`, extract `CourseIndexEntry` and `CourseSelection`

This is an atomic task — all three changes must happen together to avoid naming conflicts between SpotGolf's local types and CourseData's types.

**Files:**
- Delete: `Shared/Models/Course.swift`
- Create: `Shared/Models/CourseIndexEntry.swift`
- Create: `Shared/Models/CourseSelection.swift`

- [ ] **Step 1: Delete `Course.swift`**

Remove the file. All types it defined are now provided by CourseData (`Course`, `CourseLocation`, `SubCourse`, `Coordinate`, `Feature`, `FeatureType`) or will be extracted into their own files (`CourseIndexEntry`, `CourseSelection`).

- [ ] **Step 2: Create `Shared/Models/CourseIndexEntry.swift`**

The remote `index.json` uses `{"latitude":..., "longitude":...}` object format for coordinates, but `CourseData.Coordinate` decodes from `[lat, lon]` arrays. So `CourseIndexEntry` keeps its own simple coordinate struct for JSON decoding:

```swift
import Foundation
import CoreLocation

struct IndexCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double

    var clLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

struct CourseIndexEntry: Codable, Equatable {
    let name: String
    let coordinate: IndexCoordinate
    let holes: Int
    let path: String

    var city: String? {
        let components = path.split(separator: "/")
        guard components.count >= 4 else { return nil }
        return String(components[2])
    }

    var state: String? {
        let components = path.split(separator: "/")
        guard components.count >= 2 else { return nil }
        return String(components[1])
    }

    var country: String? {
        let components = path.split(separator: "/")
        guard components.count >= 1 else { return nil }
        return String(components[0])
    }
}
```

- [ ] **Step 3: Create `Shared/Models/CourseSelection.swift`**

```swift
import Foundation
import CourseDataSwift

struct CourseSelection: Codable, Equatable {
    let course: Course
    let selectedSubCourseIndices: [Int]

    var orderedHoles: [Hole] {
        selectedSubCourseIndices.flatMap { index in
            guard index >= 0, index < course.subCourses.count else { return [Hole]() }
            return course.subCourses[index].holes
        }
    }
}
```

Note: `Hole` here is `CourseData.Hole` (not `RoundHole`), since `CourseData` is imported.

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

This will fail with errors in files that still reference old types (`CourseHole`, `CourseGreen`, `CourseCoordinate`, `CourseFeature`). That's expected — we'll fix them in the next tasks.

- [ ] **Step 5: Commit**

```bash
git rm Shared/Models/Course.swift
git add Shared/Models/CourseIndexEntry.swift Shared/Models/CourseSelection.swift
git commit -m "Replace Course.swift with CourseData package, extract CourseIndexEntry and CourseSelection"
```

---

## Chunk 2: Service and Utility Updates

### Task 4: Update `CourseService.swift`

**Files:**
- Modify: `Shared/Services/CourseService.swift`

- [ ] **Step 1: Add import and update base URL**

Add `import CourseDataSwift` at the top. Change the base URL:

```swift
private static let baseURL = "https://raw.githubusercontent.com/SpotGolf/CourseData/main/Data/"
```

Note: `refreshIndex` continues to fetch `index.version` and `index.json` (not `.json.gz`). The index files are served uncompressed. Only course data files (`.json.gz`) are gzip-compressed.

- [ ] **Step 2: Replace compression with CourseData's gzip helpers**

Delete the `compress` and `decompress` private methods and the `CourseServiceError.compressionFailed`/`.decompressionFailed` cases.

Replace usages:
- `try compress(data)` → `try data.gzipCompressed()`
- `try decompress(compressed)` → `try compressed.gzipDecompressed()`

Update error handling: `GZipError` is thrown by CourseData's helpers, which is already an `Error`.

- [ ] **Step 3: Update `fetchCourse` to handle gzip from GitHub**

GitHub serves `.json.gz` files as raw gzip bytes. Decompress before decoding, and cache the raw compressed bytes:

```swift
func fetchCourse(path: String) async throws -> Course {
    guard let url = URL(string: Self.baseURL + path) else {
        throw CourseServiceError.invalidURL
    }

    do {
        let (data, _) = try await URLSession.shared.data(from: url)
        // Cache the raw compressed data from GitHub
        try cacheCourseData(data, forPath: path)
        // Decompress before decoding
        let decompressed = try data.gzipDecompressed()
        return try JSONDecoder().decode(Course.self, from: decompressed)
    } catch {
        if let cached = try loadCachedCourse(path: path) {
            return cached
        }
        throw error
    }
}
```

- [ ] **Step 4: Update `cacheCourseData` to store raw bytes (already compressed from GitHub)**

```swift
func cacheCourseData(_ data: Data, forPath path: String) throws {
    let coursesDir = cacheDirectory.appendingPathComponent("courses")
    let fileURL = coursesDir.appendingPathComponent(sanitizedPath(path))
    let parentDir = fileURL.deletingLastPathComponent()

    try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
    try data.write(to: fileURL)

    enforceCacheLimit()
}
```

Note: No need to append `.gz` — the path already ends in `.json.gz`.

- [ ] **Step 5: Update `loadCachedCourse` to decompress from cache**

```swift
func loadCachedCourse(path: String) throws -> Course? {
    let coursesDir = cacheDirectory.appendingPathComponent("courses")
    let fileURL = coursesDir.appendingPathComponent(sanitizedPath(path))

    guard fileManager.fileExists(atPath: fileURL.path) else {
        return nil
    }

    let compressed = try Data(contentsOf: fileURL)
    let decompressed = try compressed.gzipDecompressed()
    return try JSONDecoder().decode(Course.self, from: decompressed)
}
```

- [ ] **Step 6: Update `cacheIndex` and `loadCachedIndex` to use gzip**

```swift
func cacheIndex(data: Data, version: Int) throws {
    let compressed = try data.gzipCompressed()

    let indexFile = cacheDirectory.appendingPathComponent("index.json.gz")
    try compressed.write(to: indexFile)

    let versionFile = cacheDirectory.appendingPathComponent("index.version")
    try "\(version)".data(using: .utf8)!.write(to: versionFile)
}

func loadCachedIndex() throws -> [CourseIndexEntry]? {
    let indexFile = cacheDirectory.appendingPathComponent("index.json.gz")
    guard fileManager.fileExists(atPath: indexFile.path) else {
        return nil
    }

    let compressed = try Data(contentsOf: indexFile)
    let decompressed = try compressed.gzipDecompressed()
    return try JSONDecoder().decode([CourseIndexEntry].self, from: decompressed)
}
```

- [ ] **Step 7: Remove the `Compression` import and unused error cases**

Remove `import Compression` from the top of the file. Clean up `CourseServiceError` to only have `invalidVersion` and `invalidURL`.

- [ ] **Step 8: Commit**

```bash
git add Shared/Services/CourseService.swift
git commit -m "Update CourseService for CourseData gzip helpers and Data/ URL path"
```

---

### Task 5: Update `HoleAdvancer.swift`

**Files:**
- Modify: `Shared/Services/HoleAdvancer.swift`

- [ ] **Step 1: Rewrite `detectHole` to resolve tee feature IDs**

```swift
import CoreLocation
import CourseDataSwift

struct HoleAdvancer {
    private(set) var isPaused = false

    static let teeProximityMeters: Double = 30.0

    mutating func pause() { isPaused = true }
    mutating func resume() { isPaused = false }

    static func detectHole(location: CLLocation, courseSelection: CourseSelection) -> Int? {
        let course = courseSelection.course
        let orderedHoles = courseSelection.orderedHoles
        var closestIndex: Int?
        var closestDistance = Double.greatestFiniteMagnitude

        for (index, hole) in orderedHoles.enumerated() {
            for (_, featureID) in hole.tees {
                guard let feature = course.findFeature(id: featureID) else { continue }
                let distance = location.distance(from: feature.center.clLocation)
                if distance < teeProximityMeters && distance < closestDistance {
                    closestDistance = distance
                    closestIndex = index
                }
            }
        }
        return closestIndex
    }

    static func nearestHole(location: CLLocation, courseSelection: CourseSelection) -> Int? {
        let course = courseSelection.course
        let orderedHoles = courseSelection.orderedHoles
        guard !orderedHoles.isEmpty else { return nil }
        var closestIndex = 0
        var closestDistance = Double.greatestFiniteMagnitude

        for (index, hole) in orderedHoles.enumerated() {
            // Check tees
            for (_, featureID) in hole.tees {
                guard let feature = course.findFeature(id: featureID) else { continue }
                let d = location.distance(from: feature.center.clLocation)
                if d < closestDistance { closestDistance = d; closestIndex = index }
            }
            // Check green
            if let green = hole.green(from: course.features) {
                let d = location.distance(from: green.center.clLocation)
                if d < closestDistance { closestDistance = d; closestIndex = index }
            }
            // Check all features
            for feature in course.features(for: hole) {
                let d = location.distance(from: feature.center.clLocation)
                if d < closestDistance { closestDistance = d; closestIndex = index }
            }
        }
        return closestIndex
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Shared/Services/HoleAdvancer.swift
git commit -m "Update HoleAdvancer to resolve tee/green feature IDs via Course"
```

---

### Task 6: Update `DistanceCalculator.swift`

**Files:**
- Modify: `Shared/Utilities/DistanceCalculator.swift`

- [ ] **Step 1: Rewrite with new types**

```swift
import CoreLocation
import CourseDataSwift

struct GreenDistances {
    let front: Int
    let middle: Int
    let back: Int
}

struct FeatureDistance {
    let feature: Feature
    let distanceYards: Int
}

enum DistanceCalculator {
    private static let metersToYards = 1.09361

    static func yards(from a: CLLocation, to b: CLLocation) -> Double {
        a.distance(from: b) * metersToYards
    }

    static func yards(from a: BallMark, to b: BallMark) -> Double {
        yards(from: a.location, to: b.location)
    }

    static func formattedYards(from a: CLLocation, to b: CLLocation) -> String {
        "\(Int(yards(from: a, to: b))) yds"
    }

    static func formattedYards(from a: BallMark, to b: BallMark) -> String {
        formattedYards(from: a.location, to: b.location)
    }

    static func greenDistances(from location: CLLocation, green: Feature, direction: Vector2D) -> GreenDistances {
        GreenDistances(
            front: Int(yards(from: location, to: green.front(vector: direction).clLocation)),
            middle: Int(yards(from: location, to: green.middle().clLocation)),
            back: Int(yards(from: location, to: green.back(vector: direction).clLocation))
        )
    }

    static func featuresAhead(from location: CLLocation, features: [Feature], green: Feature) -> [FeatureDistance] {
        let greenCenter = green.center.clLocation
        let distToGreen = location.distance(from: greenCenter)

        return features.compactMap { feature in
            guard feature.type == .bunker || feature.type == .water else { return nil }

            let featureLocation = feature.center.clLocation
            let distToFeature = location.distance(from: featureLocation)
            let featureToGreen = featureLocation.distance(from: greenCenter)

            guard featureToGreen < distToGreen && distToFeature < distToGreen else { return nil }

            return FeatureDistance(
                feature: feature,
                distanceYards: Int(distToFeature * metersToYards)
            )
        }
        .sorted { $0.distanceYards < $1.distanceYards }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Shared/Utilities/DistanceCalculator.swift
git commit -m "Update DistanceCalculator for polygon-based Feature types"
```

---

### Task 7: Update `Round.swift` for CourseData imports

**Files:**
- Modify: `Shared/Models/Round.swift`

- [ ] **Step 1: Add import and update `currentCourseHole` return type**

Add `import CourseDataSwift` at the top.

Update `currentCourseHole`:

```swift
var currentCourseHole: Hole? {
    guard let selection = courseSelection else { return nil }
    let orderedHoles = selection.orderedHoles
    guard currentHoleIndex < orderedHoles.count else { return nil }
    return orderedHoles[currentHoleIndex]
}
```

Note: `Hole` here is `CourseData.Hole` since `import CourseDataSwift` is present and the local `Hole` was renamed to `RoundHole`. The property name stays `currentCourseHole` to keep the intent clear.

Also update `orderedHoles` convenience property if present:

```swift
var orderedHoles: [Hole]? {
    courseSelection?.orderedHoles
}
```

- [ ] **Step 2: Commit**

```bash
git add Shared/Models/Round.swift
git commit -m "Update Round.swift for CourseData.Hole type"
```

---

### Task 8: Update `SyncMessage.swift` and `RoundStore.swift` imports

**Files:**
- Modify: `Shared/Models/SyncMessage.swift`
- Modify: `Shared/Services/SyncService.swift`
- Modify: `Shared/Services/RoundStore.swift`

- [ ] **Step 1: Add `import CourseDataSwift` to each file**

`SyncMessage.swift` — add `import CourseDataSwift` (references `CourseSelection` which uses `CourseData.Course`).

`SyncService.swift` — add `import CourseDataSwift`.

`RoundStore.swift` — add `import CourseDataSwift`.

- [ ] **Step 2: Commit**

```bash
git add Shared/Models/SyncMessage.swift Shared/Services/SyncService.swift Shared/Services/RoundStore.swift
git commit -m "Add CourseData imports to sync and store files"
```

---

## Chunk 3: View Updates

### Task 9: Update `RoundMapView.swift`

**Files:**
- Modify: `SpotGolf/Views/RoundMapView.swift`

- [ ] **Step 1: Add import**

Add `import CourseDataSwift` at the top.

- [ ] **Step 2: Update `informationPanel` to resolve green and features via Course**

Change the section that accesses `courseHole.green` and `courseHole.features`:

```swift
if let courseHole = round.currentCourseHole,
   let course = round.courseSelection?.course,
   let green = courseHole.green(from: course.features),
   let location = locationManager.lastLocation {
    // Use centerline direction if available, otherwise fall back to player-to-green direction
    let direction: Vector2D = courseHole.vector(for: green.id, from: course.features)
        ?? Vector2D(
            dx: green.center.latitude - location.coordinate.latitude,
            dy: green.center.longitude - location.coordinate.longitude
        ).normalized()
    let greenDist = DistanceCalculator.greenDistances(from: location, green: green, direction: direction)
    let holeFeatures = course.features(for: courseHole)
    let features = DistanceCalculator.featuresAhead(from: location, features: holeFeatures, green: green)
    // ... rest of the panel stays the same
```

- [ ] **Step 3: Update `detailRows` to use `Feature` type**

Change parameter type from `[FeatureDistance]` — no change needed since `FeatureDistance` still has `.feature.type`. But update the icon logic to handle new feature types (only `.bunker` and `.water` will arrive due to filtering in `featuresAhead`):

```swift
private func detailRows(round: Round, features: [FeatureDistance]) -> [DetailRow] {
```

This stays the same since `featuresAhead` already filters to `.bunker`/`.water`.

- [ ] **Step 4: Update `panToCurrentTee` to resolve tee feature**

```swift
private func panToCurrentTee() {
    guard let round, let courseHole = round.currentCourseHole,
          let course = round.courseSelection?.course,
          let firstTeeID = courseHole.tees.values.first,
          let teeFeature = course.findFeature(id: firstTeeID) else { return }
    followsUserLocation = false
    position = .region(MKCoordinateRegion(center: teeFeature.center.clCoordinate, span: Self.defaultSpan))
}
```

- [ ] **Step 5: Commit**

```bash
git add SpotGolf/Views/RoundMapView.swift
git commit -m "Update RoundMapView for polygon-based feature resolution"
```

---

### Task 10: Update `WatchRoundView.swift`

**Files:**
- Modify: `SpotGolfWatch/Views/WatchRoundView.swift`

- [ ] **Step 1: Add import**

Add `import CourseDataSwift` at the top.

- [ ] **Step 2: Update `swingAwayView` green and feature resolution**

Change the section that accesses `courseHole.green` and `courseHole.features`:

```swift
if let round, let courseHole = round.currentCourseHole,
   let course = round.courseSelection?.course,
   let green = courseHole.green(from: course.features),
   let location = locationManager.lastLocation {
    let direction: Vector2D = courseHole.vector(for: green.id, from: course.features)
        ?? Vector2D(
            dx: green.center.latitude - location.coordinate.latitude,
            dy: green.center.longitude - location.coordinate.longitude
        ).normalized()
    let greenDist = DistanceCalculator.greenDistances(from: location, green: green, direction: direction)

    // ... green distances display stays the same ...

    let holeFeatures = course.features(for: courseHole)
    let features = DistanceCalculator.featuresAhead(
        from: location, features: holeFeatures, green: green
    )
    // ... features display stays the same ...
```

- [ ] **Step 3: Update feature display — `fd.feature.id` is now `Int`, not `String`**

The `ForEach` needs updating since `Feature.id` is now `Int`:

```swift
ForEach(features, id: \.feature.id) { fd in
```

This already works since `Int` conforms to `Hashable`. No change needed.

- [ ] **Step 4: Commit**

```bash
git add SpotGolfWatch/Views/WatchRoundView.swift
git commit -m "Update WatchRoundView for polygon-based feature resolution"
```

---

### Task 11: Update `CourseSelectionView.swift`

**Files:**
- Modify: `SpotGolf/Views/CourseSelectionView.swift`

- [ ] **Step 1: Add import**

Add `import CourseDataSwift` at the top.

- [ ] **Step 2: Update `subCourse.name` — no longer optional**

Change line 185:
```swift
// Old:
Text(subCourse.name ?? "Course \(index + 1)")
// New:
Text(subCourse.name)
```

- [ ] **Step 3: Update `defaultIndices` — `name` is no longer optional**

```swift
private func defaultIndices(for course: Course) -> [Int] {
    let names = course.subCourses.enumerated().map { ($0.offset, $0.element.name.lowercased()) }
    let frontIndex = names.first(where: { $0.1 == "front" })?.0
    let backIndex = names.first(where: { $0.1 == "back" })?.0

    if let front = frontIndex, let back = backIndex {
        return [front, back]
    }

    return Array(0..<min(2, course.subCourses.count))
}
```

- [ ] **Step 4: Commit**

```bash
git add SpotGolf/Views/CourseSelectionView.swift
git commit -m "Update CourseSelectionView for CourseData types"
```

---

## Chunk 4: Test Updates

### Task 12: Update `CourseTests.swift`

**Files:**
- Modify: `SpotGolfTests/CourseTests.swift`

- [ ] **Step 1: Rewrite test JSON and assertions for new format**

The test JSON must match CourseData's format: polygon features, integer IDs, `"coordinates"` key, centerlines, tees as feature ID references.

```swift
import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolf

final class CourseTests: XCTestCase {

    private let fullCourseJSON = """
    {
        "id": "\(UUID().uuidString)",
        "name": "Championship Course",
        "clubName": "Pine Valley Golf Club",
        "golfCourseAPIIds": [],
        "location": {
            "address": "1 Pine Valley Rd",
            "city": "Pine Valley",
            "coordinates": [39.7879, -74.9681],
            "country": "US",
            "state": "NJ"
        },
        "tees": [
            { "name": "Blue", "color": "#0000FF" },
            { "name": "White", "color": "#FFFFFF" }
        ],
        "features": [
            {
                "id": 1,
                "type": "tee",
                "polygon": [[39.7870, -74.9690], [39.7870, -74.9691], [39.7871, -74.9691], [39.7871, -74.9690], [39.7870, -74.9690]]
            },
            {
                "id": 2,
                "type": "tee",
                "polygon": [[39.7871, -74.9690], [39.7871, -74.9691], [39.7872, -74.9691], [39.7872, -74.9690], [39.7871, -74.9690]]
            },
            {
                "id": 3,
                "type": "green",
                "polygon": [[39.7880, -74.9680], [39.7880, -74.9681], [39.7882, -74.9681], [39.7882, -74.9680], [39.7880, -74.9680]]
            },
            {
                "id": 4,
                "type": "bunker",
                "polygon": [[39.7877, -74.9683], [39.7877, -74.9684], [39.7878, -74.9684], [39.7878, -74.9683], [39.7877, -74.9683]]
            },
            {
                "id": 5,
                "type": "water",
                "polygon": [[39.7875, -74.9685], [39.7875, -74.9686], [39.7876, -74.9686], [39.7876, -74.9685], [39.7875, -74.9685]]
            },
            {
                "id": 6,
                "type": "tee",
                "polygon": [[39.7885, -74.9675], [39.7885, -74.9676], [39.7886, -74.9676], [39.7886, -74.9675], [39.7885, -74.9675]]
            },
            {
                "id": 7,
                "type": "green",
                "polygon": [[39.7890, -74.9670], [39.7890, -74.9671], [39.7892, -74.9671], [39.7892, -74.9670], [39.7890, -74.9670]]
            }
        ],
        "subCourses": [
            {
                "id": "\(UUID().uuidString)",
                "name": "Front Nine",
                "holes": [
                    {
                        "number": 1,
                        "par": 4,
                        "maleHandicap": 7,
                        "femaleHandicap": 9,
                        "yardages": { "Blue": 425, "White": 400 },
                        "features": [1, 2, 3, 4, 5],
                        "tees": { "Blue": 1, "White": 2 },
                        "centerline": [[39.7870, -74.9690], [39.7875, -74.9685], [39.7881, -74.9680]]
                    }
                ],
                "tees": {}
            },
            {
                "id": "\(UUID().uuidString)",
                "name": "Back Nine",
                "holes": [
                    {
                        "number": 10,
                        "par": 5,
                        "maleHandicap": 0,
                        "femaleHandicap": 0,
                        "yardages": { "Blue": 550 },
                        "features": [6, 7],
                        "tees": { "Blue": 6 },
                        "centerline": [[39.7885, -74.9675], [39.7891, -74.9670]]
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

    func testDecodeCourseFromJSON() throws {
        let data = fullCourseJSON.data(using: .utf8)!
        let course = try JSONDecoder().decode(Course.self, from: data)

        XCTAssertEqual(course.name, "Championship Course")
        XCTAssertEqual(course.clubName, "Pine Valley Golf Club")
        XCTAssertEqual(course.location.city, "Pine Valley")
        XCTAssertEqual(course.location.state, "NJ")
        XCTAssertEqual(course.location.country, "US")
        XCTAssertEqual(course.location.address, "1 Pine Valley Rd")
        XCTAssertEqual(course.location.coordinate.latitude, 39.7879)
        XCTAssertEqual(course.location.coordinate.longitude, -74.9681)
        XCTAssertEqual(course.subCourses.count, 2)
        XCTAssertEqual(course.features.count, 7)

        let hole = course.subCourses[0].holes[0]
        XCTAssertEqual(hole.number, 1)
        XCTAssertEqual(hole.par, 4)
        XCTAssertEqual(hole.maleHandicap, 7)
        XCTAssertEqual(hole.femaleHandicap, 9)
        XCTAssertEqual(hole.tees["Blue"], 1)
        XCTAssertEqual(hole.tees["White"], 2)
        XCTAssertEqual(hole.yardages["Blue"], 425)
        XCTAssertEqual(hole.yardages["White"], 400)
        XCTAssertEqual(hole.features.count, 5)
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
        XCTAssertEqual(entry.path, "US/NJ/Pine Valley/Championship-Course.json.gz")
        XCTAssertEqual(entry.city, "Pine Valley")
        XCTAssertEqual(entry.state, "NJ")
        XCTAssertEqual(entry.country, "US")
    }

    func testGreenResolution() throws {
        let data = fullCourseJSON.data(using: .utf8)!
        let course = try JSONDecoder().decode(Course.self, from: data)
        let hole = course.subCourses[0].holes[0]

        let green = hole.green(from: course.features)
        XCTAssertNotNil(green)
        XCTAssertEqual(green?.type, .green)
    }

    func testCourseSelectionOrderedHoles() throws {
        let data = fullCourseJSON.data(using: .utf8)!
        let course = try JSONDecoder().decode(Course.self, from: data)

        let selection = CourseSelection(course: course, selectedSubCourseIndices: [0, 1])
        let holes = selection.orderedHoles

        XCTAssertEqual(holes.count, 2)
        XCTAssertEqual(holes[0].number, 1)
        XCTAssertEqual(holes[1].number, 10)
    }

    func testCourseSelectionSingleSubCourse() throws {
        let data = fullCourseJSON.data(using: .utf8)!
        let course = try JSONDecoder().decode(Course.self, from: data)

        let selection = CourseSelection(course: course, selectedSubCourseIndices: [1])
        let holes = selection.orderedHoles

        XCTAssertEqual(holes.count, 1)
        XCTAssertEqual(holes[0].number, 10)
        XCTAssertEqual(holes[0].par, 5)
    }
}
```

Note: The `fullCourseJSON` uses string interpolation for UUIDs. To avoid that, you can use fixed UUID strings like `"00000000-0000-0000-0000-000000000001"`.

- [ ] **Step 2: Commit**

```bash
git add SpotGolfTests/CourseTests.swift
git commit -m "Rewrite CourseTests for CourseData polygon format"
```

---

### Task 13: Update `CourseServiceTests.swift`

**Files:**
- Modify: `SpotGolfTests/CourseServiceTests.swift`

- [ ] **Step 1: Add import and create a helper to build a Course**

Add `import CourseDataSwift` at top.

Create a helper that builds a minimal `Course` using CourseData types:

```swift
private func makeCourse(name: String = "Test Course") -> Course {
    Course(
        name: name,
        clubName: "Test Club",
        location: CourseLocation(
            address: "123 Main St",
            city: "Phoenix",
            state: "AZ",
            country: "US",
            coordinate: Coordinate(latitude: 33.45, longitude: -112.07)
        ),
        subCourses: [
            SubCourse(name: "Front", holes: [
                Hole(number: 1, par: 4)
            ])
        ]
    )
}
```

- [ ] **Step 2: Update `testCacheAndLoadCourseData` to use new types**

```swift
func testCacheAndLoadCourseData() throws {
    let course = makeCourse()
    let data = try JSONEncoder().encode(course)
    let path = "us/az/test-course-1.json.gz"

    // Compress before caching (simulates what fetchCourse does)
    let compressed = try data.gzipCompressed()
    try service.cacheCourseData(compressed, forPath: path)

    let loaded = try service.loadCachedCourse(path: path)
    XCTAssertNotNil(loaded)
    XCTAssertEqual(loaded?.name, "Test Course")
    XCTAssertEqual(loaded?.clubName, "Test Club")
    XCTAssertEqual(loaded?.subCourses.count, 1)
    XCTAssertEqual(loaded?.subCourses[0].holes.count, 1)
}
```

- [ ] **Step 3: Update `makeEntry` and index tests to use `IndexCoordinate`**

```swift
private func makeEntry(name: String, lat: Double, lon: Double, holes: Int = 18) -> CourseIndexEntry {
    CourseIndexEntry(
        name: name,
        coordinate: IndexCoordinate(latitude: lat, longitude: lon),
        holes: holes,
        path: "US/ST/City/\(name.replacingOccurrences(of: " ", with: "-")).json.gz"
    )
}
```

Update `testCacheIndexAndLoad` to use `IndexCoordinate` instead of `CourseCoordinate`.

- [ ] **Step 4: Commit**

```bash
git add SpotGolfTests/CourseServiceTests.swift
git commit -m "Update CourseServiceTests for CourseData types and gzip compression"
```

---

### Task 14: Update `HoleAdvancerTests.swift`

**Files:**
- Modify: `SpotGolfTests/HoleAdvancerTests.swift`

- [ ] **Step 1: Rewrite helpers to build CourseData types with features**

```swift
import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolf

final class HoleAdvancerTests: XCTestCase {

    private var nextFeatureID = 1

    private func makeTeeFeature(latitude: Double, longitude: Double) -> Feature {
        let id = nextFeatureID
        nextFeatureID += 1
        let polygon = [
            Coordinate(latitude: latitude - 0.00005, longitude: longitude - 0.00005),
            Coordinate(latitude: latitude - 0.00005, longitude: longitude + 0.00005),
            Coordinate(latitude: latitude + 0.00005, longitude: longitude + 0.00005),
            Coordinate(latitude: latitude + 0.00005, longitude: longitude - 0.00005),
            Coordinate(latitude: latitude - 0.00005, longitude: longitude - 0.00005),
        ]
        return Feature(id: id, type: .tee, polygon: polygon)
    }

    private func makeGreenFeature(latitude: Double, longitude: Double) -> Feature {
        let id = nextFeatureID
        nextFeatureID += 1
        let polygon = [
            Coordinate(latitude: latitude - 0.0001, longitude: longitude - 0.0001),
            Coordinate(latitude: latitude - 0.0001, longitude: longitude + 0.0001),
            Coordinate(latitude: latitude + 0.0001, longitude: longitude + 0.0001),
            Coordinate(latitude: latitude + 0.0001, longitude: longitude - 0.0001),
            Coordinate(latitude: latitude - 0.0001, longitude: longitude - 0.0001),
        ]
        return Feature(id: id, type: .green, polygon: polygon)
    }

    private func makeSelection(holes: [Hole], features: [Feature]) -> CourseSelection {
        let subCourse = SubCourse(name: "Test", holes: holes)
        let course = Course(
            name: "Test Course",
            clubName: "Test Club",
            location: CourseLocation(
                address: "",
                city: "Test",
                state: "TX",
                country: "US",
                coordinate: Coordinate(latitude: 0, longitude: 0)
            ),
            features: features,
            subCourses: [subCourse]
        )
        return CourseSelection(course: course, selectedSubCourseIndices: [0])
    }

    override func setUp() {
        super.setUp()
        nextFeatureID = 1
    }

    func testDetectsCorrectHole() {
        let tee1 = makeTeeFeature(latitude: 33.0, longitude: -97.0)
        let green1 = makeGreenFeature(latitude: 33.005, longitude: -97.0)
        let tee2 = makeTeeFeature(latitude: 33.001, longitude: -97.0)
        let green2 = makeGreenFeature(latitude: 33.006, longitude: -97.0)
        let tee3 = makeTeeFeature(latitude: 33.002, longitude: -97.0)
        let green3 = makeGreenFeature(latitude: 33.007, longitude: -97.0)

        let holes = [
            Hole(number: 1, par: 4, features: [tee1.id, green1.id], tees: ["Blue": tee1.id], centerline: []),
            Hole(number: 2, par: 4, features: [tee2.id, green2.id], tees: ["Blue": tee2.id], centerline: []),
            Hole(number: 3, par: 4, features: [tee3.id, green3.id], tees: ["Blue": tee3.id], centerline: []),
        ]
        let features = [tee1, green1, tee2, green2, tee3, green3]
        let selection = makeSelection(holes: holes, features: features)

        let userLocation = CLLocation(latitude: 33.001, longitude: -97.0)
        let result = HoleAdvancer.detectHole(location: userLocation, courseSelection: selection)

        XCTAssertEqual(result, 1)
    }

    func testReturnsNilWhenNotNearAnyTee() {
        let tee1 = makeTeeFeature(latitude: 33.0, longitude: -97.0)
        let green1 = makeGreenFeature(latitude: 33.005, longitude: -97.0)
        let tee2 = makeTeeFeature(latitude: 33.001, longitude: -97.0)
        let green2 = makeGreenFeature(latitude: 33.006, longitude: -97.0)

        let holes = [
            Hole(number: 1, par: 4, features: [tee1.id, green1.id], tees: ["Blue": tee1.id], centerline: []),
            Hole(number: 2, par: 4, features: [tee2.id, green2.id], tees: ["Blue": tee2.id], centerline: []),
        ]
        let features = [tee1, green1, tee2, green2]
        let selection = makeSelection(holes: holes, features: features)

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

    func testNearestHole() {
        let tee1 = makeTeeFeature(latitude: 33.0, longitude: -97.0)
        let green1 = makeGreenFeature(latitude: 33.005, longitude: -97.0)
        let tee2 = makeTeeFeature(latitude: 33.01, longitude: -97.0)
        let green2 = makeGreenFeature(latitude: 33.015, longitude: -97.0)

        let holes = [
            Hole(number: 1, par: 4, features: [tee1.id, green1.id], tees: ["Blue": tee1.id], centerline: []),
            Hole(number: 2, par: 4, features: [tee2.id, green2.id], tees: ["Blue": tee2.id], centerline: []),
        ]
        let features = [tee1, green1, tee2, green2]
        let selection = makeSelection(holes: holes, features: features)

        // User is closer to hole 2 features
        let userLocation = CLLocation(latitude: 33.012, longitude: -97.0)
        let result = HoleAdvancer.nearestHole(location: userLocation, courseSelection: selection)

        XCTAssertEqual(result, 1) // index 1 = hole 2
    }

    func testResumeReEnablesAutoAdvance() {
        var advancer = HoleAdvancer()
        advancer.pause()
        advancer.resume()
        XCTAssertFalse(advancer.isPaused)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add SpotGolfTests/HoleAdvancerTests.swift
git commit -m "Rewrite HoleAdvancerTests for polygon-based feature resolution"
```

---

### Task 15: Update `DistanceCalculatorTests.swift`

**Files:**
- Modify: `SpotGolfTests/DistanceCalculatorTests.swift`

- [ ] **Step 1: Update green distance and features-ahead tests**

Add `import CourseDataSwift` at top.

Replace `testDistancesToGreen`:

```swift
func testDistancesToGreen() {
    let playerLocation = CLLocation(latitude: 33.4400, longitude: -112.07)

    // Green polygon running south-to-north
    let green = Feature(id: 1, type: .green, polygon: [
        Coordinate(latitude: 33.4420, longitude: -112.0705),
        Coordinate(latitude: 33.4420, longitude: -112.0695),
        Coordinate(latitude: 33.4430, longitude: -112.0695),
        Coordinate(latitude: 33.4430, longitude: -112.0705),
        Coordinate(latitude: 33.4420, longitude: -112.0705),
    ])
    // Direction of play: south to north
    let direction = Vector2D(dx: 1, dy: 0).normalized()

    let distances = DistanceCalculator.greenDistances(from: playerLocation, green: green, direction: direction)

    XCTAssertLessThan(distances.front, distances.middle)
    XCTAssertLessThan(distances.middle, distances.back)
    XCTAssertGreaterThan(distances.front, 0)
}
```

Replace `testFeaturesAhead` and `testFeaturesAheadSortedByDistance`:

```swift
func testFeaturesAhead() {
    let playerLocation = CLLocation(latitude: 33.4400, longitude: -112.07)

    let green = Feature(id: 1, type: .green, polygon: [
        Coordinate(latitude: 33.4450, longitude: -112.0705),
        Coordinate(latitude: 33.4450, longitude: -112.0695),
        Coordinate(latitude: 33.4460, longitude: -112.0695),
        Coordinate(latitude: 33.4460, longitude: -112.0705),
        Coordinate(latitude: 33.4450, longitude: -112.0705),
    ])

    let bunkerAhead = Feature(id: 2, type: .bunker, polygon: [
        Coordinate(latitude: 33.4420, longitude: -112.0705),
        Coordinate(latitude: 33.4420, longitude: -112.0695),
        Coordinate(latitude: 33.4425, longitude: -112.0695),
        Coordinate(latitude: 33.4425, longitude: -112.0705),
        Coordinate(latitude: 33.4420, longitude: -112.0705),
    ])

    let bunkerBehind = Feature(id: 3, type: .bunker, polygon: [
        Coordinate(latitude: 33.4380, longitude: -112.0705),
        Coordinate(latitude: 33.4380, longitude: -112.0695),
        Coordinate(latitude: 33.4385, longitude: -112.0695),
        Coordinate(latitude: 33.4385, longitude: -112.0705),
        Coordinate(latitude: 33.4380, longitude: -112.0705),
    ])

    let result = DistanceCalculator.featuresAhead(
        from: playerLocation,
        features: [bunkerAhead, bunkerBehind],
        green: green
    )

    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result.first?.feature.id, 2)
    XCTAssertGreaterThan(result.first?.distanceYards ?? 0, 0)
}

func testFeaturesAheadSortedByDistance() {
    let playerLocation = CLLocation(latitude: 33.4400, longitude: -112.07)

    let green = Feature(id: 1, type: .green, polygon: [
        Coordinate(latitude: 33.4460, longitude: -112.0705),
        Coordinate(latitude: 33.4460, longitude: -112.0695),
        Coordinate(latitude: 33.4470, longitude: -112.0695),
        Coordinate(latitude: 33.4470, longitude: -112.0705),
        Coordinate(latitude: 33.4460, longitude: -112.0705),
    ])

    let closerBunker = Feature(id: 2, type: .bunker, polygon: [
        Coordinate(latitude: 33.4410, longitude: -112.0705),
        Coordinate(latitude: 33.4410, longitude: -112.0695),
        Coordinate(latitude: 33.4415, longitude: -112.0695),
        Coordinate(latitude: 33.4415, longitude: -112.0705),
        Coordinate(latitude: 33.4410, longitude: -112.0705),
    ])

    let fartherWater = Feature(id: 3, type: .water, polygon: [
        Coordinate(latitude: 33.4435, longitude: -112.0705),
        Coordinate(latitude: 33.4435, longitude: -112.0695),
        Coordinate(latitude: 33.4440, longitude: -112.0695),
        Coordinate(latitude: 33.4440, longitude: -112.0705),
        Coordinate(latitude: 33.4435, longitude: -112.0705),
    ])

    let result = DistanceCalculator.featuresAhead(
        from: playerLocation,
        features: [fartherWater, closerBunker],
        green: green
    )

    XCTAssertEqual(result.count, 2)
    XCTAssertEqual(result[0].feature.id, 2)
    XCTAssertEqual(result[1].feature.id, 3)
    XCTAssertLessThan(result[0].distanceYards, result[1].distanceYards)
}
```

The BallMark/CLLocation distance tests at the top of the file don't reference course types and stay unchanged.

- [ ] **Step 2: Commit**

```bash
git add SpotGolfTests/DistanceCalculatorTests.swift
git commit -m "Update DistanceCalculatorTests for polygon Feature types"
```

---

### Task 16: Update `RoundTests.swift`

**Files:**
- Modify: `SpotGolfTests/RoundTests.swift`

- [ ] **Step 1: Add import and update `makeCourseSelection` helper**

Add `import CourseDataSwift` at top.

Replace `makeCourseSelection()`:

```swift
private func makeCourseSelection() -> CourseSelection {
    let greenFeature = Feature(id: 1, type: .green, polygon: [
        Coordinate(latitude: 33.0, longitude: -112.0),
        Coordinate(latitude: 33.0, longitude: -112.002),
        Coordinate(latitude: 33.002, longitude: -112.002),
        Coordinate(latitude: 33.002, longitude: -112.0),
        Coordinate(latitude: 33.0, longitude: -112.0),
    ])
    let hole1 = Hole(number: 1, par: 4, features: [1], tees: [:], centerline: [])
    let hole2 = Hole(number: 2, par: 3, features: [1], tees: [:], centerline: [])
    let subCourse = SubCourse(name: "Front", holes: [hole1, hole2])
    let location = CourseLocation(
        address: "", city: "Phoenix",
        state: "AZ", country: "US",
        coordinate: Coordinate(latitude: 33.0, longitude: -112.0)
    )
    let course = Course(name: "Test Course", clubName: "Test Club",
                        location: location, features: [greenFeature],
                        subCourses: [subCourse])
    return CourseSelection(course: course, selectedSubCourseIndices: [0])
}
```

- [ ] **Step 2: Update assertions that used string IDs**

`Course.id` is now `UUID` (not `String`) — check by name instead:

```swift
XCTAssertEqual(round.courseSelection?.course.name, "Test Course")
```

`CourseData.Hole.id` is `Int` (computed from `number`) — update assertions:

```swift
// Old: XCTAssertEqual(round.currentCourseHole?.id, "h1")
// New:
XCTAssertEqual(round.currentCourseHole?.id, 1)
XCTAssertEqual(round.currentCourseHole?.par, 4)

round.nextHole()

XCTAssertEqual(round.currentCourseHole?.id, 2)
XCTAssertEqual(round.currentCourseHole?.par, 3)
```

- [ ] **Step 3: Commit**

```bash
git add SpotGolfTests/RoundTests.swift
git commit -m "Update RoundTests for CourseData types"
```

---

### Task 17: Update `HoleTests.swift` and `RoundStoreTests.swift`

**Files:**
- Modify: `SpotGolfTests/HoleTests.swift`
- Modify: `SpotGolfTests/RoundStoreTests.swift`

- [ ] **Step 1: Replace `Hole` with `RoundHole` in both files**

In `HoleTests.swift`: Replace every `Hole(` with `RoundHole(`, `Hole()` with `RoundHole()`, `Hole.self` with `RoundHole.self`.

In `RoundStoreTests.swift`: Replace `Hole()` with `RoundHole()`, `[Hole]` with `[RoundHole]`.

- [ ] **Step 2: Commit**

```bash
git add SpotGolfTests/HoleTests.swift SpotGolfTests/RoundStoreTests.swift
git commit -m "Rename Hole to RoundHole in remaining tests"
```

---

### Task 18: Build and run all tests

- [ ] **Step 1: Build both schemes**

Run: `xcodebuild -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

Run: `xcodebuild -scheme SpotGolfWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Run unit tests**

Run: `xcodebuild test -scheme SpotGolf -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: All tests pass.

- [ ] **Step 3: Fix any remaining compilation or test errors**

Address any issues found during the build/test cycle.

- [ ] **Step 4: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "Fix remaining build/test issues from CourseData integration"
```
