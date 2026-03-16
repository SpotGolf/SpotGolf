# CourseData Package Integration Design

## Summary

Replace SpotGolf's local course model types with the shared CourseData Swift package. Update all code to use the new polygon-based data format where features (greens, tees, fairways, bunkers, water, rough) are closed polygons rather than point pairs. Update the GitHub raw URL to include the new `Data/` subdirectory.

## Motivation

The CourseData repository has moved to a polygon-based format that enables location-aware features (fairway detection, green detection, etc.). A shared Swift package now provides the canonical model types, eliminating duplication between SpotGolf and CourseBuilder.

This change only updates SpotGolf to consume the new format. No new UI features for polygon-based location awareness are included — that's future work.

## Naming Conflict Resolution

Both SpotGolf and CourseData define `Hole` and `SubCourse`. Resolution:

- **Rename SpotGolf's `Hole` to `RoundHole`** — a played hole with ball marks and stroke count
- **CourseData's `Hole`** — a course definition hole with par, features, tees, centerline
- SpotGolf's local `SubCourse` is deleted — replaced by `CourseData.SubCourse`

## Feature Resolution Pattern

In the new model, `Hole.tees`, `Hole.features`, and `Hole.green(from:)` all work with integer feature IDs that must be resolved against `Course.features`. This means any code that previously accessed embedded coordinate data on `CourseHole` now needs the full `Course` object.

`CourseSelection` already holds `course: Course`, so the features array is accessible via `courseSelection.course.features`. The following methods and views all need to pass `course.features` when resolving:

- `HoleAdvancer.detectHole` / `nearestHole` — resolve tee feature IDs to coordinates via `course.findFeature(id:)?.center`
- `DistanceCalculator.greenDistances` / `featuresAhead` — resolve green and hazard features
- `RoundMapView.informationPanel` — resolve green via `hole.green(from: course.features)`
- `WatchRoundView.swingAwayView` — same
- `RoundMapView.panToCurrentTee` — resolve tee feature to get centroid coordinate

## Changes by File

### Deleted

- **`Shared/Models/Course.swift`** — All types replaced by CourseData: `Course`, `CourseLocation`, `SubCourse`, `CourseCoordinate`, `CourseGreen`, `CourseFeature`, `FeatureType`, `CourseHole`

### New Files

- **`Shared/Models/CourseIndexEntry.swift`** — Extracted from Course.swift. Updated to use `CourseData.Coordinate` instead of `CourseCoordinate`. Stays local since CourseData doesn't provide this type.
- **`Shared/Models/CourseSelection.swift`** — Extracted from Course.swift. References `CourseData.Course` and returns `[CourseData.Hole]` from `orderedHoles`.

### Modified

**`Shared/Models/Hole.swift` → rename struct to `RoundHole`**
- Struct renamed from `Hole` to `RoundHole`
- No other structural changes

**`Shared/Models/Round.swift`**
- `holes: [Hole]` → `holes: [RoundHole]`
- `currentCourseHole` returns `CourseData.Hole?` (was `CourseHole?`)
- Add `import CourseData`

**`Shared/Services/CourseService.swift`**
- Base URL: `…/main/` → `…/main/Data/`
- Replace custom ZLIB compress/decompress with CourseData's `Data.gzipCompressed()`/`gzipDecompressed()`
- `fetchCourse`: the index paths reference `.json.gz` files. GitHub serves these as raw gzip bytes. Decompress with `gzipDecompressed()` before JSON decoding. Cache the raw (still-compressed) bytes to disk.
- Add `import CourseData`

**`Shared/Services/HoleAdvancer.swift`**
- `detectHole(location:courseSelection:)` — resolve tee feature IDs: iterate `hole.tees` values (feature IDs), call `courseSelection.course.findFeature(id:)?.center` to get coordinates for proximity check
- `nearestHole(location:courseSelection:)` — resolve greens via `hole.green(from: courseSelection.course.features)?.center`, resolve features via `courseSelection.course.features(for: hole)` and use `.center`
- Add `import CourseData`

**`Shared/Services/RoundStore.swift`**
- `Hole` → `RoundHole` references
- Add `import CourseData`

**`Shared/Utilities/DistanceCalculator.swift`**
- `FeatureDistance`: uses `Feature` instead of `CourseFeature`
- New signature: `greenDistances(from: CLLocation, green: Feature, direction: Vector2D) -> GreenDistances`
  - Front: `green.front(vector: direction).clLocation`
  - Middle: `green.middle().clLocation`
  - Back: `green.back(vector: direction).clLocation`
- New signature: `featuresAhead(from: CLLocation, features: [Feature], green: Feature) -> [FeatureDistance]`
  - Uses `feature.center.clLocation` for distance calculations
  - Filter to only hazard types: `.bunker` and `.water` (exclude `.fairway`, `.green`, `.tee`, `.rough`)
- Add `import CourseData`

**`SpotGolf/Views/CourseSelectionView.swift`**
- `subCourse.name ?? "Course \(index + 1)"` → `subCourse.name` (no longer optional)
- Add `import CourseData`

**`SpotGolf/Views/RoundMapView.swift`**
- `informationPanel`: resolve green via `courseHole.green(from: course.features)`, compute direction via `courseHole.vector(for: greenFeature.id, from: course.features)`, pass to `greenDistances`
- Resolve hole features via `course.features(for: courseHole)` for `featuresAhead`
- `panToCurrentTee`: resolve first tee feature ID → `course.findFeature(id:)?.center.clCoordinate`
- Add `import CourseData`

**`SpotGolfWatch/Views/WatchRoundView.swift`**
- `swingAwayView`: same green/feature resolution pattern as RoundMapView
- `courseHole.green` → `courseHole.green(from: course.features)`
- `courseHole.features ?? []` → `course.features(for: courseHole)` filtered to `.bunker`/`.water`
- Add `import CourseData`

**`Shared/Models/SyncMessage.swift`**
- Add `import CourseData` (references `CourseSelection` which uses CourseData types)

**`Shared/Services/SyncService.swift`**
- No structural changes — `CourseSelection` is still Codable
- Add `import CourseData`

### Project Configuration

- Add `https://github.com/SpotGolf/CourseData` as a Swift Package dependency in `SpotGolf.xcodeproj`
- Link CourseData to both iOS and watchOS targets
### Tests

Affected test files:
- **`CourseTests.swift`** — Replace all old types (`CourseHole`, `CourseGreen`, `CourseCoordinate`, `CourseFeature`, `SubCourse`, `Course`, `CourseLocation`) with CourseData equivalents. Update string IDs to UUIDs.
- **`CourseServiceTests.swift`** — Update `Course` construction to use UUID IDs and CourseData types. Update compression tests for gzip format.
- **`HoleAdvancerTests.swift`** — Replace old types with CourseData equivalents. Construct full `Course` with features array for tee/green resolution.
- **`DistanceCalculatorTests.swift`** — Replace `CourseGreen`/`CourseFeature` with `Feature` polygons. Add `Vector2D` direction parameters.
- **`RoundTests.swift`** — Update course construction, `Hole` → `RoundHole`.
- **`RoundStoreTests.swift`** — `Hole` → `RoundHole`.
- **`HoleTests.swift`** — `Hole` → `RoundHole`.

## What's Not Changing

- `BallMark` model — unchanged
- `LocationManager` — unchanged
- `SyncService` transport logic — unchanged
- `SyncMessage` structure — unchanged (just type imports)
- Round persistence format — `RoundHole` encodes/decodes identically to old `Hole`
- Cache directory structure — unchanged
- UI layout and behavior — unchanged (same information displayed, just sourced differently)

