# Hole starts follow strokes

The Hole Times editor goes away. Instead, a hole's start moves both ways as its strokes change. Today a start can only be added or moved earlier, so the editor is the only way to fix a start that is too early.

The case this fixes: on hole 4, a stroke is added to hole 5 at hole 4's tee by mistake. Hole 5 then starts early in hole 4. Deleting the stroke leaves that start, so hole 4's GPS track ends a moment after it began, its suggestions show on hole 5, and exported swings and contacts from hole 4 are labeled hole 5. Cancel on a new spot's sheet (7da2d50) leaves a start behind in the same way.

## 1. Strokes keep their origin and hit time

```swift
/// Where a stroke came from.
enum StrokeOrigin: Codable, Equatable {
    case manual                // placed by hand; its time is the GPS fix nearest the spot
    case suggestion(id: UUID)  // taken from a suggestion; keeps the suggestion's time
}
```

- New fields on `Stroke`:
  - `origin: StrokeOrigin`
  - `hitAt: Date?`. It is nil for a manual stroke placed when the start window (section 3) had no GPS.
- `Stroke`'s `init(from:)` and `encode(to:)` add `origin` and `hitAt`.
- `RoundStore.moveStroke` builds a new `Stroke` and must carry over `origin` and `hitAt`.
- `addStroke` loses its `hitAt` parameter and reads `stroke.hitAt` instead.

## 2. Rules

| Event | Stroke's time | Hole start |
|---|---|---|
| Spot placed by hand | Nearest fix in the start window | Add rule |
| Suggestion taken | The suggestion's time | Add rule |
| Manual stroke moved | Worked out again at the new spot | Add rule with the new time, then recompute |
| Suggestion stroke moved | Kept | No change |
| Stroke removed (Delete, or Cancel on a new spot) | None | Recompute. A suggestion stroke's suggestion shows again (section 5). |

**Add rule** (today's `Round.strokeHit`, without its `.userSet` check): a hole with no start gets one at the hit time. A hit before the start moves the start back.

**Recompute** changes every start except hole 0's, which is the round start. In an imported round, the first move or remove of a stroke on a hole replaces that hole's estimated start with stroke times.

| Hole's strokes after the change | Start |
|---|---|
| None | `startedAt = nil`, version + 1 |
| Any | The earliest stroke time, version + 1 if it changed |

- A manual stroke with no `hitAt` gets a time from the start window for the recompute. That time isn't saved.
- If a stroke still has no time because there is no GPS, the start doesn't change.
- The new start must fall after the start of the closest earlier hole that has one, and before the start of the closest later hole that has one. Otherwise nothing changes.
- `RoundStore.removeStroke` and `moveStroke` take an `estimatedTime` closure, since `StrokeFinder` is phone only. `SpotActions.remove` and `SpotActions.move` build it from the start window. They are used by the delete alert in `RoundMapView`, `SpotActions.cancel`, and the drags in `RoundMapLayer` and `GreenView`.

## 3. Start window

Today a spot placed by hand gets the time of the nearest fix in the hole's track. That track begins at the hole's start, so a spot placed by hand can never move the start earlier. When a start is too late, the stops before it also show as suggestions on the previous hole, not this one.

`HoleTrack.startWindow(_:in:holeIndex:)` returns the fixes after the start of the closest earlier hole that has one, and before the start of the closest later hole that has one. The hole's own start is not used, so the window does not depend on the start it sets.

- Manual strokes get their time from this window: when added, when moved, and in a recompute when they have no `hitAt`.
- `RoundMapView.filterTrack()` works out the window together with `holeTrack`. It passes the window to `RoundMapLayer`, `GreenView`, `SpotEditSheet`, `SpotActions.addSpot` and `SpotActions.cancel`, and to the `moveStroke` calls at `RoundMapLayer.swift:186` and `GreenView.swift:246`.
- Once a spot placed by hand moves a start back, that hole's earlier stops show as suggestions on it again.

## 4. Timeline

- `HoleStart.startedAt` becomes `Date?`. Nil means the hole has no start.
  - A cleared entry keeps its id, and its version goes up by 1, so `HoleTimeline.merge` keeps it over the watch's older copy.
  - Deleting the entry would not work. The watch sends its timeline back in its application context, and the merge would add the entry back.
- `HoleTimeline.normalized`: entries with a start are sorted and filtered as today. Entries without a start come after them, ordered by hole.
- `startHole` and `strokeHit` treat a hole whose entry has no start as a hole with no entry. The first new stroke sets the time on that same entry and adds 1 to its version.
- `HoleStart.source` and `HoleStartSource` are deleted. `Round.init`, `startHole(_:at:source:)`, `strokeHit` and `TrackImporter.holeTimeline` stop passing a source.
- `HoleTimeline.holeIndex(at:)` and `possibleHoles` skip entries with no start, and so do `HoleTrack` and `TrackExporter`, through them. `Round.startOfHole(_:)` gives one hole's start.

## 5. Suggestions

- A suggestion is hidden while a stroke's origin holds its ID. The `hidden` set passed to `StrokeFinder.suggestions` is the strokes' suggestion IDs.
- Deleting a suggestion stroke, or cancelling its sheet when it is new, shows the suggestion again. `RoundMapView` already refreshes suggestions on every round change, through `filterTrack()`.
- Delete `Round.hiddenSuggestionIDs`, its `onChange` at `RoundMapView.swift:114`, and `RoundStore.hideSuggestion` and `showSuggestion`. Remove `suggestionID` from `SpotSelection` if nothing else uses it.
- There is no way to dismiss a suggestion. A wrong one stays on the map, and the user ignores it.

## 6. Removing the editor

| Item | Change |
|---|---|
| `HoleTimelineView.swift` | Delete |
| Hole times button and `showHoleTimes` in `MapButtonBar`, sheet at `RoundMapView.swift:181` | Delete |
| `RoundStore.setTimeline`, `setStartTime`, `startTimeRange` | Delete |
| `RoundTests` 286 | Tests that `strokeHit` leaves a `.userSet` start alone. Delete. |
| Tests that build a `HoleStart` with a source or check one | Drop the source |
| "Hole Times", "Round start", "Estimated", "Corrected", "Set by you" | Remove each one from the string catalog that is no longer used |
| `RoundStoreTests` 279–296, `SyncFlowTests` 1222–1225, `PastRoundUITests` 83–91 | Delete |
| `GreenViewUITests` 59 | Uses the Hole times button to confirm edit mode. Check something else. |

After this, decision 4 in `2026-10-18-remove-edit-mode.md` has only the Log button left to place.

## Checks

1. `Round` recompute:
   - Removing the only stroke clears the start.
   - Removing the earliest of several strokes moves the start to the next earliest.
   - A manual stroke with no `hitAt` gets a time from the window. With no GPS, the start doesn't change.
   - Hole 0's start doesn't change.
   - An imported hole's estimated start moves to its earliest stroke time.
2. Wrong-hole case: a stroke on hole 5 at hole 4's tee, then removed. Hole 4's track is whole again.
3. Cancel on a new spot's sheet takes back the start the spot made. For a suggestion, the suggestion shows again.
4. Moves:
   - A manual first stroke dragged to the tee moves the start earlier.
   - Dragged to a later spot, it moves the start later.
   - A suggestion stroke that is dragged keeps its time, and the start stays.
5. A deleted suggestion stroke's suggestion shows again.
6. A new stroke on a hole with a cleared start reuses the entry: same id, higher version.
7. `SyncFlowTests`: a cleared entry wins over the watch's older copy, and both devices end with the same timeline.
8. `SyncCodecTests`:
   - A stroke of each origin, with and without `hitAt`.
   - A `HoleStart` with nil `startedAt`.
9. `HoleTrack.startWindow` bounds: no earlier start, no later start, both.
10. UI tests pass with the Hole times button gone.
