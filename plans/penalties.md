# Penalties Feature

## Overview

Allow players to mark where bad shots went (penalty areas, out of bounds) by placing pins on the map. This follows the app's ethos of marking ball locations on the course.

## User Flow

1. Player hits a bad shot (two cases):
   - **Penalty area**: Ball went into a red penalty area (e.g., water). Player will take a drop.
   - **Out of bounds**: Player isn't sure if the ball is OB. They'll hit a provisional.
2. Player long-presses the map to drop a pin where they estimate the ball went.
3. Player taps the pin to open the edit sheet.
4. Edit sheet now has two new buttons: **"Mark out of bounds"** and **"Mark as penalty"**.
5. Tapping either button sets the mark type, changes pin color, and dismisses the sheet.
6. No automatic stroke adjustment — stroke count comes naturally from the marks the player places.

## Pin Colors

| Mark Type | Color |
|-----------|-------|
| Regular   | Blue  |
| Penalty   | Red   |
| Out of Bounds | White |

## Model Changes

### BallMark

Add a `type` enum to `BallMark`:

```swift
enum BallMarkType: String, Codable {
    case regular
    case penalty
    case outOfBounds
}
```

Add `var type: BallMarkType = .regular` to `BallMark`. Default to `.regular` so existing marks and the "At my ball" flow are unaffected.

### RoundStore

Add a method to update a mark's type:

```swift
func setMarkType(_ mark: BallMark, type: BallMarkType, in roundID: UUID)
```

This finds the mark, updates its type, saves, and syncs.

### SyncMessage

No new sync case needed. The `addMark` case already syncs the full `BallMark` struct which will now include the type. Add a new case for type updates:

```swift
case setMarkType(UUID, BallMarkType, UUID)  // markID, type, roundID
```

## View Changes

### RoundMapView — Pin Colors

Update `spotMarker` to use `mark.type` for color:
- `.regular` → blue circle
- `.penalty` → red circle
- `.outOfBounds` → white circle (with dark border for visibility)

### RoundMapView — Edit Sheet

Add two buttons to `spotEditSheet`:
- **"Mark as penalty"** — sets `mark.type = .penalty`, dismisses sheet
- **"Mark out of bounds"** — sets `mark.type = .outOfBounds`, dismisses sheet

If the mark is already typed, show a **"Clear penalty/OB"** button to reset to `.regular`.

## Implementation Steps

1. Add `BallMarkType` enum and `type` property to `BallMark`
2. Add `setMarkType` to `Round` and `RoundStore`
3. Add `setMarkType` sync message case
4. Update pin colors in `RoundMapView` based on mark type
5. Add penalty/OB buttons to the edit sheet
6. Update unit tests
7. Update UI tests
