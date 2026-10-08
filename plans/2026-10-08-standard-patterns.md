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
| `@Model final class Round` | `@Attribute(.unique) id`, `date`, `status`, `endedAt`, `resumedFromEnd`, `strokesVersion`, `streamBase`, `lastSeq`, `endConfirmed`, `hiddenSuggestionIDs: Set<UUID>` (phone only), and the Codable structs `holes`, `holeTimeline`, `displayHole`, `courseSelection`, `pins` | `struct Round` in `rounds.json` |
| `@Model final class StreamEntry` | `roundID`, `index`, `timestamp`, `record: Data` (the 25-byte record, as the watch sends it) | `streams/<id>_watch.stream` |
| Hidden suggestions | `Round.hiddenSuggestionIDs` | `suggestions.json`, `SuggestionStore` |

- `RoundHole`, `Stroke`, `HoleStart`, `DisplayHole`, `PinLocation` and `CourseSelection` stay `Codable` structs, stored inside `Round`.
- `Round` keeps its computed properties and methods. Its `mutating` methods become plain methods.
- `SuggestionStore` is deleted. Hiding a suggestion is a `RoundStore` method.

### Stores

| Store | After |
|---|---|
| `RoundStore` | Holds the `ModelContext`. Still the only place that changes rounds, so it can send `RoundEvent`s. `update(_:_:)` changes the model in place and saves. The early return for "no change" compares the Codable fields before and after |
| `StreamStore` | Same methods. `append` inserts one `StreamEntry` per record. `truncate` deletes entries from an index on. `count` and `records` fetch by `roundID`, sorted by `index`. The in-memory cache stays |

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
- UI tests reset both keys at launch, since `UserDefaults` is not in memory like the model container.

### Container

- One `ModelContainer` per app, for `Round` and `StreamEntry`. Built in `PhoneServices` / `WatchServices`.
- On disk normally. In memory for UI tests (`ModelConfiguration(isStoredInMemoryOnly: true)`), which replaces clearing `rounds` at launch.
- The root view gets `.modelContainer(container)`.

### Views

- `RoundListView` uses `@Query(sort: \Round.date, order: .reverse)`.
- Views that show one round look it up by ID from `RoundStore` as now. They do not change rounds directly.

### Tests

- A test helper `makeTestContainer()` returns an in-memory container. `RoundStoreTests`, `StreamStore` tests, sync tests and `RoundSimulator` use it instead of temporary folders.
- Tests that compare `Round` values compare their fields, since `Round` is now a class.

## 6. `feature/split-round-map`: smaller `RoundMapView`

`RoundMapView.swift` (1,105 lines, 20 `@State`) is split into these files under `SpotGolf/Views/RoundMap/`:

| File | Contents (functions now in `RoundMapView`) |
|---|---|
| `RoundMapView.swift` | Screen layout, sheets, alert, `onChange` handlers |
| `HoleHeaderView.swift` | `holeHeader`, `scoreBox`, `holeCircle`, `selectHole`, `holeSummary` |
| `RoundMapLayer.swift` | `mapView`, `spotMarker`, `pinFlag`, `hazardBubbles`, `hazardBubble`, `suggestionPin`, `targetLines`, `lineEnd`, `strokeColor` |
| `MapInfoOverlay.swift` | `overlayView`, `keyInformation`, `targetInformation`, `keyInformationBox` |
| `MapButtonBar.swift` | `buttonBar`, `setPinButton`, `mapButtons` |
| `SpotEditSheet.swift` | `spotEditSheet` |
| `MapShapes.swift` | `BubbleArrow`, `FlagShape` |

Logic moves out of views into code with unit tests:

| Logic | New home |
|---|---|
| `bearing(from:to:)`, `shownHoleHeading` | `Shared/Utilities/HoleCamera.swift` |
| Camera position from `panToHole` | `HoleCamera.position(for:holeIndex:mapSize:)` |
| `updateMetersPerPoint` math | `HoleCamera.metersPerPoint(_:)` |
| `reloadTrack`, `filterTrack` | `SpotGolf/Utilities/HoleTrack.swift` |
| `yardsToPin`, `feetToGreenCenter`, `yardsFromTargetToPin`, `hazardsAhead` | `HoleOverview` |
| `insertionIndex`, `convertSuggestion` | `RoundStore` |

- State that belongs together becomes one struct: the camera (`position`, `followsUserLocation`, `hasInitialPan`, `cameraChanges`, `mapSize`, `metersPerPoint`) and the spot drag (`draggingStroke`, `dragOffset`).
- Accessibility identifiers do not change, so UI tests do not change.

## 7. `feature/swift6`: Swift 6 language mode

- `SWIFT_VERSION: "6.0"` for every target in `project.yml`.
- Fix every error. Expected kinds:

  | Kind | Fix |
  |---|---|
  | Delegate callbacks from CoreLocation, CoreMotion, HealthKit and WatchConnectivity | `nonisolated` delegate methods that hop to the main actor with `Task { @MainActor in }` or `MainActor.assumeIsolated` where the API calls on the main thread |
  | Values crossing actors | `Sendable` on value types; `sending` or copies where needed |
  | `[String: Any]` payloads | Encode before crossing, as `SyncCodec` does |
  | Static mutable state | `let`, or `@MainActor` |
  | Test classes | `@MainActor` on test cases that touch stores |

- No `@unchecked Sendable` or `nonisolated(unsafe)` unless a comment says why it is safe.

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
