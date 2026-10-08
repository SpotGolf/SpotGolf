# Standard patterns

Moves the phone and watch apps onto Apple's current patterns, in eight branches. Each branch is finished and merged to `main` before the next starts.

## Decisions

| Topic | Decision |
|---|---|
| Branches | One per item, in the order below |
| Persistence | SwiftData for rounds, hidden suggestions and stream records. No conversion of old data: the app is treated as new |
| Settings | `@AppStorage` (`UserDefaults`), Apple's pattern for user preferences |
| Files that stay files | Putt capture files and the downloaded course cache |
| Swift | Swift 6 language mode, tests included |
| Localization | English String Catalog only |
| Deployment targets | Stay at iOS 17 and watchOS 10 |
| Watch messages | No change in any branch |

## Order

```
1 async-events ─▶ 2 observation ─▶ 3 app-services ─▶ 4 launch-options
      ─▶ 5 swiftdata ─▶ 6 split-round-map ─▶ 7 swift6 ─▶ 8 string-catalog
```

- Events come before Observation, because `@Observable` removes the `$property` publishers the Combine code uses.
- SwiftData comes before the map split, so the new subviews are written against the final data API.
- Swift 6 comes late, so it does not fix code that earlier branches delete.

## 1. `feature/async-events`: one event style

State changes are observed through SwiftUI (`onChange`). Events between services are closures that run during the change, in order, so messages to the other device keep their order. Combine and `NotificationCenter` are removed. (`AsyncStream` was dropped: it delivers later, which could reorder sync messages.)

| Now | After |
|---|---|
| `RoundStore.onTimelineChanged`, `onDisplayHoleChanged`, `onPinsChanged`, `onStrokesChanged` | `RoundStore.addListener((RoundEvent) -> Void)`. `RoundEvent` cases: `timelineChanged`, `displayHoleChanged`, `pinsChanged`, `strokesChanged` (local changes, sent to the other device), and `roundsChanged` (any change). Several listeners, run in the order added |
| `RoundTracker`: `rounds.$rounds.sink`, `location.$lastLocation.sink` | `rounds.addListener`, `location.addLocationListener` |
| `RoundTracker`: `NotificationCenter` `didBecomeActiveNotification` | `scenePhase` `.active` in `PhoneRootView` calls `roundTracker.appBecameActive()` |
| `PinShareCoordinator`: `rounds.$rounds.sink` | `rounds.addListener` |
| `WatchAppDelegate`: two Combine pipelines | `rounds.addListener` and `workoutManager.addRunningListener`, both calling one method that acts only on changes |
| `PuttCaptureRecorder`: workout sink | `workoutManager.addRunningListener` |
| `RoundMapView`, `WatchRoundView`: `.onReceive($lastLocation)`, `.onReceive($rounds)`, `.onReceive($hidden)` | `.onChange(of:)`, with `initial: true` where the publisher sent its first value at once |
| Sensor and transport closures (`onRawLocations`, `onSwing`, `onContact`, `onFileReceived`, ...) | No change: already closures |

- A Combine sink on `@Published` ran once at subscription. Each replacement makes that first call itself, so a round active at launch is still picked up.

## 2. `feature/observation`: `@Observable`

| Now | After |
|---|---|
| `final class X: ObservableObject` (17 classes) | `@Observable final class X` |
| `@Published var` | `var`. `private(set)` stays where it is now |
| `@StateObject` | `@State` |
| `@EnvironmentObject var x: X` | `@Environment(X.self) private var x` |
| `.environmentObject(x)` | `.environment(x)` |
| `@ObservedObject` | Plain `let`, or `@Bindable` where a binding is needed |
| Properties views must not track (caches, counts, listeners) | `@ObservationIgnored` |

- `StreamStore.revision` stays, as an observed counter.
- `RoundStore.rounds` keeps `didSet { save() }` until branch 5.

## 3. `feature/app-services`: one environment value per app

| App | Container | Holds |
|---|---|---|
| Phone | `@Observable @MainActor final class PhoneServices` | `roundStore`, `locationManager`, `roundTracker`, `syncService`, `phoneSync`, `courseService`, `suggestionStore`, `settingsStore`, `streamStore`, `permissions`, `pinShare`, `puttCaptures` |
| Watch | `@Observable @MainActor final class WatchServices` | `roundStore`, `locationManager`, `syncService`, `watchSync`, `workoutManager`, `permissions`, `puttCapture`, `captureUploader`, `contactMonitor`, `streamStore`, and privately the swing detector and hole advancer |

- The container builds and wires every service in its `init`. Wiring now in `SpotGolfApp.init` and `WatchAppDelegate.applicationDidFinishLaunching` moves there.
- The root view gets `.environment(services)`. Views read `@Environment(PhoneServices.self) private var services` and use `services.roundStore`. Property names match the names views used before. Observation tracks each property a view reads, so a view still redraws only for what it uses.
- `WatchAppDelegate` holds the `WatchServices`, calls `start()` in `applicationDidFinishLaunching`, and passes workout launches and recovery to it, so recording still resumes on a background launch.
- The apps have no SwiftUI previews, so none need a container.

## 4. `feature/launch-options`: test switches in one place

```swift
struct LaunchOptions {
    var isUITesting: Bool
    var keepsRounds: Bool      // watch: --keep-rounds
    var startsRound: Bool      // watch: --start-round
    static let current = LaunchOptions(arguments: CommandLine.arguments)
}
```

- Launch arguments do not change, so the UI tests do not change.
- `PhoneServices(options:)` and `WatchServices(options:)` choose the parts once:

  | Part | Normal | UI testing |
  |---|---|---|
  | Permission source | `PhonePermissionSource` / `SystemPermissionSource` | `GrantedPermissionSource` |
  | Pin sharing | `CloudKitPinSharing` | `NoPinSharing` |
  | Watch required to start a round | Yes | No |
  | Live Activity | Shown | Not shown |
  | Saved data | On disk | In memory (from branch 5); empty at launch until then |

- `RoundListView` reads `services.requiresWatch`, and `WatchRoundView` reads `services.showsWorkoutStatus`, instead of `CommandLine.arguments`.
- `LaunchOptions` is in `Shared/Utilities`, with unit tests for reading the arguments.
- After this branch, `CommandLine.arguments` appears only in `LaunchOptions`.

## 5. `feature/swiftdata`: SwiftData storage

Breaking change: rounds saved by earlier builds are not read. Old JSON files are left on disk, unread.

### Models

| Model | Fields | Replaces |
|---|---|---|
| `@Model final class Round` | `@Attribute(.unique) id`, `date`, `status`, `endedAt`, `resumedFromEnd`, `strokesVersion`, `streamBase`, `lastSeq`, `endConfirmed`, `hiddenSuggestionIDs: [UUID]` (phone only). `holes`, `holeTimeline`, `displayHole`, `courseSelection` and `pins` are saved as encoded JSON data, decoded once when first read | `struct Round` in `rounds.json` |
| `@Model final class StreamEntry` | `roundID`, `index`, `record: Data` (the 25-byte record, as the watch sends it) | `streams/<id>_watch.stream` |
| Hidden suggestions | `Round.hiddenSuggestionIDs` | `suggestions.json`, `SuggestionStore` |

- `RoundHole`, `Stroke`, `HoleStart`, `DisplayHole`, `PinLocation` and `CourseSelection` stay `Codable` structs. They are saved as encoded data, not as SwiftData's own nested values: `CourseSelection` holds the whole course, and SwiftData's support for deeply nested structs is unreliable.
- Reading one of those values also reads its saved data, so views and observers see it change.
- `Round` keeps its computed properties and methods. Its `mutating` methods become plain methods.
- `SuggestionStore` is deleted. Hiding a suggestion is `RoundStore.hideSuggestion`.

### Stores

| Store | After |
|---|---|
| `RoundStore` | Holds the `ModelContext` and `rounds`, newest first. Still the only place that changes rounds, so it can send `RoundEvent`s. `update(_:_:)` changes the round object and saves. Every change adds 1 to `revision`, which views watch with `onChange`, since an array of round objects does not change when a round's fields do |
| `StreamStore` | Same methods. `append` inserts one `StreamEntry` per record and saves. `truncate` and `delete` delete entries. Record counts per round are read once at launch and kept up to date. A round "has a stream" when it has at least one record. The in-memory cache stays |

### Settings

- `SettingsStore`, `AppSettings` and `settings.json` are deleted.
- Keys and defaults live in one place:

  ```swift
  enum SettingsKey {
      static let stationaryThreshold = "stationaryThreshold"  // default 30
      static let sharePins = "sharePins"                      // default true
  }
  ```

- `SettingsView` and the round map use `@AppStorage(SettingsKey.sharePins) private var sharePins = true`, and the same for `stationaryThreshold`.
- `PinShareCoordinator` reads `UserDefaults.standard` through a `sharesPins` closure, as it does now, so tests still pass their own value.
- `PhoneServices` registers the defaults with `UserDefaults.standard.register(defaults:)` at launch, so code outside views gets the same defaults.
- UI tests reset both keys at launch, since `UserDefaults` keeps values between runs.

### Container

- One `ModelContainer` per app, for `Round` and `StreamEntry`, made by `Storage.container(for:)`. Built in `PhoneServices` / `WatchServices`.
- `cloudKitDatabase: .none`: the phone has a CloudKit container for shared pins, and SwiftData would otherwise try to sync the store to it.
- UI tests delete the store at launch unless `--keep-rounds` is passed, as they cleared `rounds.json` before. Every launch uses the same store file: watchOS can relaunch the app itself, without the test's arguments, to recover a running workout, so a separate test store or one in memory would lose the round.
- The root view gets `.modelContainer(container)`.

### Views

- `RoundListView` uses `@Query(sort: \Round.date, order: .reverse)`.
- Views that show one round look it up by ID from `RoundStore` as now. They do not change rounds directly.

### Tests

- `Storage.inMemoryContainer()` gives each test an empty store. Tests that reload open a new `ModelContext` on the same container instead of a new store on the same folder.
- Tests that compare `Round` values compare their fields, since `Round` is now a class. JSON round-trip tests become save-and-reload tests; tests of the old JSON format are deleted.

## 6. `feature/split-round-map`: smaller `RoundMapView`

`RoundMapView.swift` (1,100 lines, 20 `@State`) is split into these files under `SpotGolf/Views/RoundMap/`:

| File | Contents |
|---|---|
| `RoundMapView.swift` | Screen layout, sheets, alert, `onChange` handlers, the GPS track and suggestions |
| `RoundMapState.swift` | `MapCameraState` (position, following, first pan, camera moves, map size, meters per point) and `SpotSelection` (the spot being edited, its new place, the delete confirmation) |
| `HoleHeaderView.swift` | The hole circles, back button, score box and hole summary |
| `RoundMapLayer.swift` | The map: spots and dragging them, the track, the target and its lines, hazard bubbles, suggestions, and the gestures |
| `MapInfoOverlay.swift` | The hole's distances and the target's, with the button that clears the target |
| `MapButtonBar.swift` | Edit, set pin, hole times and location buttons |
| `SpotEditSheet.swift` | The spot sheet |
| `MapMarkers.swift` | `PinFlag`, `TargetMarker`, `HazardBubble`, `SuggestionPin`, `BubbleArrow`, `FlagShape` |

Logic moves out of views into code with unit tests:

| Logic | New home |
|---|---|
| Bearing, the hole's heading, the hole camera, the following camera, meters per point, where the target's lines stop, the flag's scale | `SpotGolf/Utilities/MapGeometry.swift` |
| Picking out a hole's track | `SpotGolf/Utilities/HoleTrack.swift` |
| Hole summary, feet to the green, hazards ahead | `HoleOverview` |
| Turning a suggestion into a stroke in the right order | `RoundStore.addSuggestedStroke` in `SpotGolf/Services/RoundStore+Suggestions.swift`: it uses `StrokeFinder`, which only the phone has |

- The drag state (`draggingStroke`, `dragOffset`) lives in `RoundMapLayer`, the only view that uses it.
- The following camera, built the same way in two places, is now one function.
- Accessibility identifiers do not change, so UI tests do not change.

## 7. `feature/swift6`: Swift 6 language mode

- `SWIFT_VERSION: "6.0"` for every target in `project.yml`.
- Errors found and how each was fixed:

  | Error | Fix |
  |---|---|
  | `static let` of a type that is not Sendable (`ISO8601DateFormatter`, `[String: Any]`, `CourseSelection`) | `Date.ISO8601FormatStyle`, which is Sendable; computed `static var`; `CourseSelection: Sendable` |
  | `CourseDataSwift` types are not marked Sendable | `@preconcurrency import CourseDataSwift` in `CourseSelection.swift`, until the package marks them |
  | WatchConnectivity's session passed into a main-actor task | Read the received context before the task |
  | Sensor batches and capture details passed between threads | Pass the count and a copy instead |
  | `Activity` is not Sendable, so the main actor can't call its async methods | `RoundTracker` updates and ends activities in detached tasks that look them up by ID |
  | `PinSharing` passed into async calls | `PinSharing: Sendable`; the test fake is `@MainActor` |
  | Main-actor test classes with synchronous `setUp`/`tearDown` | `setUp() async throws` and `tearDown() async throws`; UI test classes are `@MainActor` |

- Every `@unchecked Sendable` has a comment saying why it is safe. No `nonisolated(unsafe)`.

## 8. `feature/string-catalog`: String Catalog

- `Localizable.xcstrings` for the phone app, the watch app and the Live Activity, in English.
- SwiftUI `Text("...")` literals are found by the compiler. Strings built in code (for example `syncError` in `SpotGolfApp`) use `String(localized:)`.
- Log messages and accessibility identifiers are not localized.
- `project.yml` adds the catalogs to each target; `SWIFT_EMIT_LOC_STRINGS: YES`.

## Each branch

1. Make the session's simulator clones, named for the branch (CLAUDE.md).
2. `xcodegen generate` after adding or moving files.
3. Build both schemes, and run unit and UI tests for both apps on the clones.
4. Run the app on the clones and check the screens the branch touched.
5. Ask before completing the branch.

## Versioning

| Branch | Release kind |
|---|---|
| 5 `swiftdata` | Breaking (saved rounds): MINOR |
| All others | `refactor`: PATCH |
