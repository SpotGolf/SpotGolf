# Removing Edit Mode

An analysis of removing Edit Mode from the round map, so the app has one mode that always shows suggestions and allows stroke edits. Nothing has been changed yet.

## 1. What Edit Mode controls today

| Behavior | Not editing | Editing | Where |
|---|---|---|---|
| Suggestion pins | Not worked out, not shown | Shown | [RoundMapView.swift:293](../SpotGolf/Views/RoundMap/RoundMapView.swift#L293), [RoundMapLayer.swift:62](../SpotGolf/Views/RoundMap/RoundMapLayer.swift#L62) |
| Tap on map | Drops a distance target (active round only) | Nothing | [RoundMapLayer.swift:114](../SpotGolf/Views/RoundMap/RoundMapLayer.swift#L114) |
| Tap on a spot | Shows/hides lines between strokes | Opens the spot sheet | [RoundMapLayer.swift:138](../SpotGolf/Views/RoundMap/RoundMapLayer.swift#L138) |
| Long press on map | Nothing | Adds a spot | [RoundMapLayer.swift:124](../SpotGolf/Views/RoundMap/RoundMapLayer.swift#L124) |
| Drag a spot | Nothing | Moves it | [RoundMapLayer.swift:154](../SpotGolf/Views/RoundMap/RoundMapLayer.swift#L154) |
| Bottom middle | Set pin button | Suggestion legend | [MapButtonBar.swift:41](../SpotGolf/Views/RoundMap/MapButtonBar.swift#L41) |
| Hole times and Log buttons | Hidden | Shown | [MapButtonBar.swift:110](../SpotGolf/Views/RoundMap/MapButtonBar.swift#L110) |
| Shown hole | Follows the watch's display hole | Stays on the edited hole until Done | [RoundMapView.swift:126](../SpotGolf/Views/RoundMap/RoundMapView.swift#L126) |
| Flag raised over suggestions | No | Yes | [RoundMapLayer.swift:78](../SpotGolf/Views/RoundMap/RoundMapLayer.swift#L78) |

Green View turns editing on when it opens and off when its X is tapped ([RoundMapView.swift:103](../SpotGolf/Views/RoundMap/RoundMapView.swift#L103), [RoundMapView.swift:156](../SpotGolf/Views/RoundMap/RoundMapView.swift#L156)).

## 2. Code changes

| File | Change |
|---|---|
| `RoundMapView.swift` | Remove `isEditing`, `editingHoleIndex`, `editsAfterHoleChange` and the `onChange` blocks for them. Suggestions always run. `editHole` becomes "show hole". |
| `RoundMapLayer.swift` | Remove `isEditing` and every guard on it. Choose what a tap on a spot does (decision 1). |
| `MapButtonBar.swift` | Remove the Edit button. Find new places for the legend, Hole times and Log. |
| `GreenView.swift`, `RoundMapState.swift` | Mostly comments. The hold rule in `GreenViewState.holeChanged` changes (decision 2). |
| `ScorecardView.swift:210` | The Edit column becomes a "show hole" column, or is removed. |

There is no change to saved rounds or watch messages, so this is not a breaking change under the versioning rules. The watch app and Live Activity have no Edit Mode.

## 3. Decisions to make

1. **What a tap on a spot does.** Today it opens the sheet in Edit Mode and toggles the stroke lines otherwise. One mode allows only one of these.
   - Recommendation: a tap opens the sheet, and the stroke lines are always on, as they already are in Green View.
2. **Holding the shown hole.** Today `editingHoleIndex` keeps the phone on a hole while the watch's GPS moves the display hole on. Without it, during a live round:
   - The map can switch holes while you are fixing a stroke.
   - Green View closes as soon as the watch moves to the next hole, because a hole change closes it ([RoundMapState.swift:103](../SpotGolf/Views/RoundMap/RoundMapState.swift#L103)). That can happen while you are still marking putts.
   - Recommendation: hold the hole while the spot sheet is open, a drag is in progress, or Green View is open.
3. **Crowding at the bottom middle.** On the green during a round, the Set pin button and the suggestion legend both apply, and today they share one slot.
4. **Where Hole times and Log go.** Showing them all the time makes five buttons on the right. A menu would avoid that.

## 4. Issues during play

| Issue | Detail |
|---|---|
| Accidental edits | A 0.5 s long press adds a spot, and a 0.3 s press on a spot starts a drag. Both would now work on the screen used during the whole round, including while walking. |
| Suggestions for the current stop | A stop still in progress counts once it passes the minimum length ([StrokeFinder.swift:362](../SpotGolf/Services/StrokeFinder.swift#L362)). So a pin appears under your blue dot while you stand at the ball, and it moves as the stop's center is worked out again. |
| No way to dismiss a wrong suggestion | The only way to hide one is to take it and then delete the stroke. Wrong pins would stay on the main map. |
| Map clutter | Suggestion pins, the player's dot, the target and its lines, and hazard bubbles all appear together on the play screen. |
| Work on the main thread | `StrokeFinder` goes over the whole round's GPS. It would run on every stream batch (the watch sends one every 5 s, [WatchServices.swift:123](../SpotGolfWatch/WatchServices.swift#L123)) and on every round change. Today it runs only while editing. Measure it on a device with a full 18-hole round. |

## 5. What breaks

| Area | Items |
|---|---|
| UI test helper | `StrokeEditing.startEditing` taps `EditHole`. `addStroke(at:)` calls it, and ClubSelection, PenaltyFlow and PastRound tests use that. |
| UI tests | `SuggestionLegendUITests.testTheLegendShowsOnlyWhileEditing`, `MapTargetUITests.testTapWhileEditingDoesNotShowTarget`, `GreenViewUITests` lines 59–71, `PastRoundUITests` lines 69, 83–89 and 184–190, `LogUITests` line 70 |
| Strings | "Edit", "Done" and "Edit hole %@" become stale in the string catalog |
| Plans | `2026-10-17-green-view.md`, `2026-10-09-scorecard.md`, `2026-10-06-pin-location.md`, `2026-09-29-stroke-finder-design.md`, `2026-10-10-current-round-log.md`, `2026-10-01-missed-swings.md` item 18 |
| Code comments | The doc comments in `RoundMapLayer`, `MapButtonBar`, `GreenView` and `GreenViewState` describe Edit Mode |
