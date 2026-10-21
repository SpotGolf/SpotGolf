# Remove Edit Mode: Plan

Branch: `feat/remove-edit-mode`

## Step 1: Delete Edit Mode

Remove the mode and every map feature that works only while editing. Green View keeps working as it does now.

### `RoundMapView.swift`

1. Delete `isEditing`, `editingHoleIndex`, `editsAfterHoleChange`.
2. Delete `onChange(of: isEditing)` and the `onChange(of: greenView.isShown)` block that sets `isEditing`.
3. In `onChange(of: shownHoleIndex)`, delete the three editing lines.
4. `shownHoleIndex(_:)`: delete the `editingHoleIndex` branch.
5. `selectHole`: delete `editingHoleIndex = nil`.
6. Delete `editHole`. `ScorecardView` no longer takes a closure.
7. Green View's X: delete `isEditing = false`.
8. `refreshSuggestions`: delete the `isEditing` check, so Green View always gets suggestions.
9. Stop passing `isEditing` to `RoundMapLayer` and `MapButtonBar`.

### `RoundMapLayer.swift`

1. Delete `isEditing`.
2. Delete the suggestion pins. Pass `[]` to `hasPinsOnGreen` for the flag.
3. Delete the long press that adds a spot.
4. Delete the spot drag gesture, `draggingStroke`, `dragOffset`, `dropPoint`, `dropLift`.
5. Move `showsStrokeLines` to `RoundMapView` and pass it in. A tap on a spot does nothing.
6. Tap on the map: delete `!isEditing` from the guard.
7. Delete any helper that is now unused.

### `MapButtonBar.swift`

1. Delete `isEditing`, the Edit/Done button, and the Log button.
2. Left capsule: Green View button over a ruler button (`ruler` symbol). The ruler toggles `showsStrokeLines`, which shows and hides the lines and distances between strokes. Blue when on, secondary when off. Label "Distances", identifier `StrokeLines`. Rename `editCapsule` to `leftCapsule`.
3. Bottom middle: `SuggestionLegend` always shown, with `setPinButton` above it when it applies.
4. Delete `showLog` and the Log sheet in `RoundMapView`.

### Other code

| File | Change |
|---|---|
| `ScorecardView.swift` | Delete the `.edit` column and `editHole` |
| `GreenView.swift`, `RoundMapState.swift`, `MapButtonBar.swift` | Remove "edit mode" from comments |
| `Localizable.xcstrings` | Delete `"Edit"` and `"Edit hole %lld"`. Keep `"Done"`. Add `"Distances"`. |

### Tests

| File | Change |
|---|---|
| `SuggestionLegendUITests.swift` | Legend always shows. On the green, Set Pin shows above it. |
| New `StrokeLinesUITests.swift` | Ruler shows the lines and distances; tapping it again hides them |
| `StrokeEditing.swift` | Delete `startEditing`. Tests that add or edit strokes on the map are deleted or skipped until step 2. |
| `MapTargetUITests.swift` | Delete `testTapWhileEditingDoesNotShowTarget` |
| `GreenViewUITests.swift` | Delete the `EditHole` and `RoundLog` checks (lines 59–71) |
| `PastRoundUITests.swift` | Delete the scorecard Edit test (lines 175–190) and other `EditHole` uses |
| `LogUITests.swift` | Delete the test that opens the log from the map |

Run `xcodegen generate`. Build. Run the changed test files.

Commit: `feat!: Remove edit mode from the round map`

## Step 2: Track the Round on the Main Map

### Suggestions

1. `RoundMapLayer`: show suggestion pins at all times. Tap takes the suggestion (`SpotActions.takeSuggestion`).
2. Pass `suggestions` to `hasPinsOnGreen` for the flag.
3. `RoundMapView`: read `scenePhase`.
   - On `.active`, call `reloadTrack()`.
   - In `onChange(of: streamStore.revision)`, skip when not `.active`.
4. Measure `StrokeFinder.suggestions` on the phone with a full 18-hole round. If it's over 50 ms, keep the found stops and extend them from the newest fix.

### Spots

1. Long press on the map adds a spot (`SpotActions.addSpot`).
2. Long press on a spot drags it (`SpotActions.move`).
3. Tap on a spot opens its sheet.

### Buttons

1. Log button always shown above the map capsule.

### Scorecard

1. Tap on a hole row closes the scorecard and shows that hole (`selectHole`). It does not hold the hole.

### Hole hold

1. During a round, while a spot's sheet is open, a spot is dragged, or Green View is open, the map stays on its hole when the watch moves the display hole on (`HoleHold`). The hold ends with the edit, or when the user picks a hole.

### Tests

| Test | Checks |
|---|---|
| `StrokeEditing` | `addStroke(at:)` long presses with no Edit step. Re-enable the step 1 skips. |
| `MapTargetUITests` | Tap on the map shows a target; tap on a spot opens its sheet |
| `PastRoundUITests` | Tap on scorecard hole 2 shows hole 2 |
| `LogUITests` | Log opens from the map |
| `RoundMapView` | A stream batch while in the background does not refresh; returning to `.active` does |

Run `xcodegen generate`. Build. Run the changed test files.

Commit: `feat: Track strokes and suggestions on the main map`
