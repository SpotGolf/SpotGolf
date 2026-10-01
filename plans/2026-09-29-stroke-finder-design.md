# Stroke Finder and Strokes

## Summary

One part of the code, `StrokeFinder`, looks at a round's GPS and swings. It says where the player probably hit the ball, with any club: driver, woods, irons, wedges or putter. The same pass decides when each hole starts.

It relies on golf being linear. The player moves over time from one ball location to the next, and that path runs from hole to hole:

```
tee 1 ─► stroke ─► stroke ─► green 1 ─► (walk) ─► tee 2 ─► stroke ─► green 2 ─► (walk) ─► tee 3 ...
                             └─ hole 1 ends when the player leaves green 1 for the last time
```

The project also switches from "marks" and "guesses" to golf's own words:

| Word | Meaning |
|---|---|
| **Stroke** | A place the player hit the ball from, saved in the round. Replaces "mark". |
| **Stroke suggestion** | A place `StrokeFinder` thinks the player hit the ball from, and also the watch's raw swing. Replaces "guess", "shot", "mark suggestion" and "swing". |

## Decisions

| Topic | Decision |
|---|---|
| One place | `StrokeFinder` holds every rule for finding strokes and hole starts. Nothing else guesses ball locations. `TrackStopFinder`, `ShotGuesser`, `MarkSuggester` and `HoleTimelineFixer` are folded into it or deleted. |
| One suggestion model | `StrokeSuggestion` replaces `Swing`, `ShotGuesser.Shot`, `MissedMarkGuess`, `MarkSuggestion` and `TrackStop`. Finding stops becomes private code inside `StrokeFinder`. |
| Watch swings | The watch records a swing as a `StrokeSuggestion` with only a time and peak force. The stream's binary format does not change. |
| Hole starts | `StrokeFinder` decides them on the phone, replacing `HoleTimelineFixer`. The watch's `HoleAdvancer` stays for live play, and the phone corrects its entries later. |
| End of a hole | Hole k ends when the player leaves hole k's green for the last time before hole k+1's tee. An overhit approach followed by a walk back to the green still works, because the walk back is the later visit. |
| Swings | A swing made while standing still can be a stroke, using today's `ShotGuesser` rules. |
| Putts | Suggested. A soft swing on the green is no longer dropped. |
| Standing still with no swing | Suggested only near the green, as a possible chip or putt. The watch's 10 g swing threshold misses most putts. |
| Stationary Threshold setting | Kept. It is the shortest stop with no swing near the green that is suggested (default 30 s). It matters more once the watch records putts below 10 g. |
| When it runs | Hole starts are worked out over the whole round when new GPS or swings arrive. Suggestions are worked out when a hole is shown on the map, from that hole's GPS only, which runs from its start to the next hole's start. |
| Saved suggestions | Suggestions are not saved, only the IDs of ones dismissed or converted to strokes. The file is `suggestions.json`. |
| Old data | Not kept. The app isn't released, so saved rounds, `guesses.json`, queued sync messages and old CSV headers don't need to load. Delete the apps from the simulators and devices after the change. |
| Suggestion IDs | Worked out from the start time of the stop the suggestion was made in, for both kinds. Stops are found over the whole round's GPS, so a moved hole start never changes them. See [Suggestion IDs](#suggestion-ids). |
| Stroke times | `Stroke` has no time. A long-pressed stroke's time would be when it was placed, not when it was hit. A stroke's order in its hole is its stroke number. |
| Estimated stroke time | When code needs to know when a stroke was hit, `StrokeFinder.estimatedTime(of:in:)` gives the time of the nearest fix in that hole's GPS. Only placing a converted suggestion uses it today. |
| Strokes and suggestions | A suggestion is hidden only when it is dismissed or converted to a stroke, by its ID. A long-pressed stroke hides nothing, because the player may be adding strokes between duffs. There is no distance rule. |
| Stroke count | `strokes.count`. Every stroke, including putts, counts. Today's count is `marks.count - 1`. Distances stay "this stroke to the next one". |
| Hand-set hole starts | Never moved (`source == .userSet`). |
| Imported rounds | The importer sets only the round start, and `StrokeFinder` works out the hole starts. The `hole` column in the CSV is ignored. |
| Limit per hole | Up to 10 suggestions per hole. |

## Renames

| Before | After |
|---|---|
| `BallMark`, `BallMark.swift` | `Stroke`, `Stroke.swift` |
| `BallMarkType` (`regular`, `penalty`, `outOfBounds`) | `StrokeType`, same cases |
| `RoundHole.marks` | `RoundHole.strokes` |
| `Round.marksVersion`, `marksSnapshot`, `allMarks`, `marks`, `addMark`, `hasMark` | `strokesVersion`, `strokesSnapshot`, `allStrokes`, `strokes`, `addStroke`, `hasStroke` |
| `RoundStore.addMark`, `moveMark`, `setMarkType`, `reorderMark`, `onMarksChanged` | `addStroke`, `moveStroke`, `setStrokeType`, `reorderStroke`, `onStrokesChanged` |
| `MarksSnapshot`, `SyncMessage.marks`, `SnapshotSync.sendMarks`, `sendsMarks` | `StrokesSnapshot`, `.strokes`, `sendStrokes`, `sendsStrokes` |
| `DistanceCalculator.yards(from: BallMark, to:)` | Takes `Stroke` |
| `Swing`, `ShotGuesser.Shot`, `MissedMarkGuess`, `MarkSuggestion`, `TrackStop` | `StrokeSuggestion` |
| `GuessStore`, `guesses.json` | `SuggestionStore`, `suggestions.json` |
| `MarkSuggester.swift`, `MissedMarkGuess.swift`, `ShotGuesser.swift`, `TrackStops.swift`, `HoleTimelineFixer.swift` | Deleted. The code moves to `StrokeFinder.swift` and `StrokeSuggestion.swift`. |
| `HoleStartSource.corrected` comment "to fit the marks" | "from the GPS path" |
| CSV row type `mark`, column `markType` | `stroke`, `strokeType` |
| UI text: "mark", "Mark as penalty", "Mark out of bounds", "Add suggested mark", "Mark Suggestions", "N marks" | "stroke", "Penalty stroke", "Out of bounds", "Add suggested stroke", "Stroke Suggestions", "N strokes" |
| Accessibility IDs: `SpotMark_N`, `MarkAsPenalty`, `MarkOutOfBounds` | `Stroke_N`, `StrokePenalty`, `StrokeOutOfBounds` |
| Location permission text: "to mark where your ball is" | "to record where you hit the ball" |
| Tests, including UI tests: `BallMarkTests`, `MarkSuggesterTests`, `MissedMarkGuessTests`, `GuessStoreTests` | `StrokeTests`, or moved into the `StrokeFinder` tests |

Left alone:
- `// MARK:` comments.
- SF Symbol names such as `xmark` and `exclamationmark`.
- Old plans in `plans/`.

## Models

```swift
/// A place the player hit the ball from, saved in the round.
struct Stroke: Identifiable, Codable, Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    var type: StrokeType
}

/// A place the player may have hit the ball from. The watch records a swing as one with
/// no location; StrokeFinder adds the location.
struct StrokeSuggestion: Identifiable, Equatable {
    enum Kind: Equatable {
        case swing(peakG: Float)          // the watch felt a swing
        case stop(duration: TimeInterval) // the player stood still near the green
    }
    let timestamp: Date    // the swing, or the start of the stop
    let kind: Kind
    var latitude: Double?  // nil until StrokeFinder places it
    var longitude: Double?
    var id: UUID           // from the start time of its stop (see Suggestion IDs)
}
```

- **Stream:** `StreamRecord.swing` holds a `StrokeSuggestion`. It writes and reads the same 25 bytes as today: kind 1, milliseconds, peak force, then zero bytes.
- **Codable:** `Stroke`, `Round` and `RoundHole` use the Codable code Swift writes for them. `BallMark`'s hand-written decoder is removed.

## Suggestion IDs

A suggestion's ID is a fixed UUID built from the millisecond start time of the stop it was made in. It is built the same way as `MissedMarkGuess.id(forSwingAt:)` today, without the round ID, because dismissals are saved per round.

```
round GPS ──► stops (whole round, same every time)
                 │
                 └─ stop start time ──► ID
                       (the same whatever swing wins, and whether or not a swing is ever added)
```

| Case | ID |
|---|---|
| Practice swings, then the real swing, in one stop | Same. The ID doesn't depend on which swing wins. |
| A stop near the green later gets a swing (low-g putts) | Same. The kind changes, but the stop doesn't. |
| A hole start moves | Same. Stops are found over the whole round, not one hole's piece. |
| A stop still in progress | Same. Its start is its first fix, and only its end grows. |
| New GPS and swings arrive | Earlier stops don't change, because data is only added to |
| A re-tee after the 90 s practice window | New ID. It's a new stroke. |
| A stop-finder constant is tuned | New IDs. Dismissals are lost, which is acceptable. |

A raw swing from the watch has not been placed in a stop yet. Its ID comes from its own time until `StrokeFinder` places it.

## Hole starts

`StrokeFinder.holeStarts(round:points:swings:) -> [HoleStart]` runs over the whole round and returns the fixed timeline.

For each move from hole k to hole k+1:

```
1. Find hole k+1's anchor, after the player's first visit to hole k's green
   ├─ first swing within teeArrivalRadius of hole k+1's tee, else
   └─ first fix within teeArrivalRadius of hole k+1's tee
2. Look back from the anchor for the last fix on hole k's green or within greenEdgeMargin of its edge
   ├─ found     ──► hole k+1 starts at the next fix after it
   └─ not found ──► hole k+1 starts at the anchor (no green data, or the ball was picked up)
3. Keep the start after hole k's start and before hole k+2's start
```

- **Skipped holes:** A hole the watch jumped over, or a hole after the last entry (an imported round), gets an entry wherever steps 1 and 2 find one.
- **Tee passed early:** The anchor only counts after the player has been to hole k's green, so walking past hole k+1's tee on the way does not start it.
- **Sources:** A moved entry becomes `.corrected`, and a filled-in entry is `.estimated`. A `.userSet` entry is never moved.
- **Repeat runs:** Running it again on its own result changes nothing.
- **Stroke changes:** Stroke changes no longer trigger it, because strokes don't affect hole starts.

Walnut Creek, holes 1 to 2:

| Time | Event | Hole today | Hole after |
|---|---|---|---|
| 14:22:46 | Last putt on green 1 | 1 | 1 |
| 14:23:28 | Last fix within 10 m of green 1's edge | 1 | 1 |
| 14:23:29 to 14:25:53 | Walk to tee 2 and wait | 1 | 2 |
| 14:25:53 | Tee shot on hole 2 | 2 | 2 |

## Suggestions on one hole

`StrokeFinder.suggestions(in:holeIndex:points:swings:minStop:hidden:) -> [StrokeSuggestion]` gets the whole round's GPS and swings. It finds stops over the whole round, then keeps the stops that end on the hole: the hole the player was on when they walked away. A stop picks up a few fixes as the player slows down, so its start can fall a few seconds before the hole does. `minStop` is the Stationary Threshold setting.

```
stops in the round's GPS that end on this hole (private stop finder: 5 m radius, 8 s minimum, 2 GPS spikes allowed)
   │
   ├─ stop with swings ──► today's ShotGuesser rules
   │                        · last swing in a stop wins (earlier ones were practice)
   │                        · tee swings less than 90 s apart are one stroke
   │                        · a new stop must be closer to the green to be a new stroke (not on the green, where every putt counts)
   │                        · stop more than 60 m from the centerline is off the hole
   │                        · on the green: every swing's stop counts (putts), no peak-force limit
   │
   └─ stop with no swing ──► suggested only on the green or within chipZoneMargin of its edge
                             and at least minStop long (chips and putts)
```

Then:
- Hide dismissed and converted IDs.
- Keep the first 10, in time order.

New constants, to be tuned on the Walnut Creek round:

| Constant | Start value | Meaning |
|---|---|---|
| `greenEdgeMargin` | 10 m | A fix on the green or this close to its edge counts as at the green, for the end of the hole. Covers GPS drift (about 5 m) and the fringe. |
| `chipZoneMargin` | 30 m | A stop with no swing on the green or this close to its edge can be a chip or putt. Covers greenside bunkers and chips. |
| `teeArrivalRadius` | 10 m | A fix or swing this close to a tee box counts as reaching it. Only GPS drift: a ball hit over the green can land 20 m from the next tee. |

Both are measured from the green's edge, and anywhere inside the green is 0 m. From the Broadlands course data:

| Measure (18 greens) | Smallest | Typical | Largest |
|---|---|---|---|
| Green area | 495 m² | about 580 m² | 724 m² |
| Longest distance across a green | 29 m | about 36 m | 42 m |
| Nearest bunker to the green's edge | 1 m | 2 to 3 m | 71 m |
| Green edge to the next hole's tee | 22 m | about 60 m | 106 m |

A next tee can be inside the chip zone (22 m). This is fine: once the player leaves the green, those fixes are on the next hole, whose chip zone is around its own green.

## Where it runs

```
StreamBatch arrives ──► StreamReceiver stores records
                    └─► PhoneSync.fixTimeline ──► StrokeFinder.holeStarts (at most every 5 s, whole round)
                                                   └─► RoundStore.setTimeline (sent to the watch)

Map shows hole k ──► round GPS + hole k's swings (hole range from the timeline)
                 └─► StrokeFinder.suggestions ──► map pins
```

- **Map:** `RoundMapView` works out suggestions when the shown hole changes, when edit mode opens, and when new records, strokes or timeline changes arrive for the shown hole.
- **Hole starts:** `holeStarts` also always runs once when the round ends and once after an import.
- **Converting a suggestion:** Its ID is saved with the dismissed IDs, so it is no longer shown. The new stroke goes before the first stroke whose estimated time is later than the suggestion's time.

## Files

| File | Change |
|---|---|
| `Shared/Services/StrokeFinder.swift` | New. `holeStarts`, `suggestions`, `estimatedTime`, private stop finder, `HoleShape`, constants |
| `Shared/Models/StrokeSuggestion.swift` | New |
| `Shared/Models/Stroke.swift` | Was `BallMark.swift`. No time. |
| `Shared/Models/StreamRecord.swift` | `Swing` removed. `.swing` holds a `StrokeSuggestion`. Same bytes. |
| `Shared/Models/Round.swift`, `RoundHole.swift`, `SyncMessage.swift`, `HoleStart.swift` | Renames |
| `Shared/Services/ShotGuesser.swift`, `TrackStops.swift`, `HoleTimelineFixer.swift`, `MarkSuggester.swift`, `Shared/Models/MissedMarkGuess.swift` | Deleted |
| `Shared/Services/GuessStore.swift` | Becomes `SuggestionStore.swift`. Dismissed and converted IDs per round, in `suggestions.json`. |
| `Shared/Services/RoundStore.swift`, `Shared/Services/Sync/*` | Renames. `StreamReceiver.processSwings` removed. `fixTimeline` uses `StrokeFinder.holeStarts`, at most every 5 s. |
| `Shared/Services/StreamStore.swift` | `swings(for:)` returns `[StrokeSuggestion]` |
| `Shared/Utilities/DistanceCalculator.swift`, `TrackExporter.swift`, `TrackImporter.swift` | Renames. The exporter writes stroke rows with a blank time, after the timed rows. The importer reads the new header only, and sets only the round start. |
| `simulate-round.sh` | Expects the new header |
| `Data/*.csv` | Converted once to the new header, with `mark` rows renamed `stroke` and their times cleared |
| `SpotGolf/Views/*`, `SpotGolfWatch/*`, `Info.plist` files | Renames and UI text. `RoundMapView` uses `StrokeFinder.suggestions`. |
| `SpotGolfWatch/SwingDetector.swift`, `SwingPeakFinder.swift` | Produce `StrokeSuggestion` |

## Tests

| Test | Checks |
|---|---|
| `StrokeFinderHoleStartTests` | Leaving the green starts the next hole; an overhit and walk back; no green data falls back to tee arrival; skipped holes; `.userSet` not moved; running twice changes nothing |
| `StrokeFinderSuggestionTests` | Today's `ShotGuesserTests` and `TrackStopFinder` cases; putts on the green; a no-swing stop near the green is suggested; a no-swing stop in the fairway is not; stable IDs (practice then real swing, stop that gains a swing, moved hole start, stop in progress); dismissed and converted hidden; a long-pressed stroke next to a suggestion hides nothing; limit of 10; estimated stroke time |
| `StrokeFinderRealRoundTests` | Walnut Creek: hole starts are within about 30 s of the player leaving each green, and strokes per hole are compared with the scorecard. Fixes the wrong CSV path in the test today. |
| `StrokeTests`, `RoundTests`, `RoundStoreTests` | Renames. `strokeCount == strokes.count`. |
| `StreamRecordTests` | A swing's bytes are the same as before |
| `SuggestionStoreTests` | Dismissed and converted IDs survive a reload |
| `SyncFlowTests`, `SyncCodecTests` | Renames. Swing-to-guess tests become: a stream arrives, then the timeline is fixed. |
| `TrackExporterTests`, `TrackImporterTests` | New header. The old header is refused. |
| UI tests | New accessibility IDs and text |

## Order of work

1. Rename marks to strokes across the project, including the CSV, the files in `Data/` and UI text. Remove `Stroke`'s time and change the stroke count. Tests pass.
2. Add `StrokeSuggestion` and use it for the watch's swings and in the stream. Tests pass.
3. Add `StrokeFinder.holeStarts` with the green rule. Point `PhoneSync.fixTimeline` at it. Delete `HoleTimelineFixer`.
4. Add `StrokeFinder.suggestions` with the private stop finder, putts and near-green stops. Delete `ShotGuesser`, `TrackStopFinder` and `MarkSuggester`'s code.
5. Switch `RoundMapView` to `StrokeFinder.suggestions`. Replace `GuessStore` with `SuggestionStore`. Remove `processSwings` and `MissedMarkGuess`.
6. Change the importer to set only the round start.
7. Tune the constants on Walnut Creek.
