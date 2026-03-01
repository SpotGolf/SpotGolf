# SpotGolf Implementation Plan

## Context
Building a simple golf ball tracking app for iOS and watchOS. The core interaction is tapping "At my ball" to record GPS location. Rounds group marks together. The Watch acts as a convenient remote with distance display, syncing to the iPhone app which shows a map.

## Architecture

**SwiftUI + CoreLocation + MapKit + WatchConnectivity**

Shared code lives in `Shared/`, platform-specific code in `SpotGolf/` (iOS) and `SpotGolfWatch/` (watchOS).

### Data Model (Shared)
- `BallMark` — id, coordinate (lat/lon), timestamp
- `Round` — id, name/date, array of BallMarks, isActive flag

### Key Services (Shared)
- `LocationManager` — CLLocationManager wrapper, ObservableObject, requests GPS fix on demand
- `RoundStore` — persists rounds as JSON to documents directory, ObservableObject

### iOS App
- `RoundListView` — list of rounds, button to start new round
- `RoundMapView` — MapKit view showing pins for all marks in a round, "At my ball" button
- `WatchSyncService` — WCSession delegate, receives marks from Watch

### watchOS App
- `WatchRoundView` — "At my ball" button, shows distance to previous mark
- `PhoneSyncService` — WCSession delegate, sends marks to iPhone

## File Structure
```
SpotGolf/
├── project.yml                  # xcodegen config
├── Shared/
│   ├── Models/
│   │   ├── BallMark.swift
│   │   └── Round.swift
│   ├── Services/
│   │   ├── LocationManager.swift
│   │   └── RoundStore.swift
│   └── Utilities/
│       └── DistanceCalculator.swift
├── SpotGolf/
│   ├── SpotGolfApp.swift
│   ├── Views/
│   │   ├── RoundListView.swift
│   │   ├── RoundMapView.swift
│   │   └── ContentView.swift
│   ├── Services/
│   │   └── WatchSyncService.swift
│   ├── Assets.xcassets/
│   └── Info.plist
├── SpotGolfWatch/
│   ├── SpotGolfWatchApp.swift
│   ├── Views/
│   │   └── WatchRoundView.swift
│   ├── Services/
│   │   └── PhoneSyncService.swift
│   ├── Assets.xcassets/
│   └── Info.plist
```

## Implementation Steps

### Step 1: Install xcodegen & create project.yml
- `brew install xcodegen`
- Write `project.yml` with iOS app target, watchOS app target, and shared source groups

### Step 2: Shared data models
- `BallMark.swift` — Codable struct with id (UUID), latitude, longitude, timestamp
- `Round.swift` — Codable struct with id, date, marks array, isActive

### Step 3: Shared services
- `LocationManager.swift` — wraps CLLocationManager, provides `requestLocation()`, publishes last known coordinate
- `RoundStore.swift` — loads/saves rounds as JSON, provides active round, add mark to active round
- `DistanceCalculator.swift` — compute distance between two coordinates using CLLocation.distance(from:)

### Step 4: iOS app views
- `SpotGolfApp.swift` — app entry point, injects RoundStore and LocationManager as environment objects
- `ContentView.swift` — NavigationStack with RoundListView
- `RoundListView.swift` — list rounds, "New Round" button, tap to view round on map
- `RoundMapView.swift` — Map with annotations for each BallMark, "At my ball" button that gets location and adds mark

### Step 5: watchOS app views
- `SpotGolfWatchApp.swift` — app entry point
- `WatchRoundView.swift` — large "At my ball" button, distance to previous mark display, current round status

### Step 6: WatchConnectivity sync
- `WatchSyncService.swift` (iOS) — WCSessionDelegate, receives messages with new BallMarks, adds to active round
- `PhoneSyncService.swift` (watchOS) — WCSessionDelegate, sends BallMark data to iPhone on each mark

### Step 7: Generate Xcode project
- Run `xcodegen generate`

## Persistence
Simple JSON file storage via `RoundStore`. No need for CoreData/SwiftData for this scope.

## Verification
1. Run `xcodegen generate` to produce the .xcodeproj
2. Open in Xcode, build for iOS Simulator and watchOS Simulator
3. Test: start round → tap "At my ball" → verify pin appears on map
4. Test: mark from Watch → verify it syncs to iPhone app
