# The display hole and the hole timeline

The cases this is for are in `2026-10-03-hole-advance-improvements.md`.

## Problem

The round has one "current hole": the last entry in the hole timeline. `HoleAdvancer` moves it from the watch's GPS, and "Play this hole" moves it by hand. So a wrong hole change from the GPS also puts a wrong start time in the timeline, which decides which hole every GPS fix and swing belongs to. And looking at another hole needs "Resume round" to get back, because the view and the round share the one hole.

## Design

The round keeps two separate things.

| | Display hole | Hole timeline |
|---|---|---|
| What it is | The hole both devices show: distances, strokes, map | When each hole started |
| Changed by | The watch's GPS (`HoleAdvancer`); the arrows on the watch; the hole circles on the phone | A stroke added to a hole; a start time edited by hand in Hole Times |
| Stored as | `Round.displayHole: DisplayHole` (hole index, time of the last change) | `Round.holeTimeline: [HoleStart]` |
| Synced as | `SyncMessage.displayHole`, and in `SyncContext` and `StartRound`. The later change wins | `SyncMessage.holeTimeline` as before |

"Play this hole" and "Resume round" are removed on both devices. The arrows and circles change the display hole directly, and the other device follows.

### The timeline from strokes

A stroke has no time of its own. When one is added, the phone works out when it was hit:

| How it was added | Time |
|---|---|
| A suggestion was converted | The suggestion's time: the swing, or the start of the stop |
| Placed on the map by hand | The time of the GPS fix nearest to it on the hole shown |

Then `Round.strokeHit(onHole:at:)` changes the timeline:

```
hole has no start           → add one at that time, source .stroke
                              (only if it falls between the starts of the holes around it)
hole has a start, stroke    → move the start back to the stroke's time
  was hit before it           (never for a start the user set by hand)
otherwise                   → no change
```

`HoleStartSource` loses `autoAdvance` and `playHole` and gains `stroke`.

### GPS for a hole with no start yet

The suggestions and the dotted GPS track for a hole come from the fixes on that hole. Until a hole has a stroke it has no start, so its fixes still read as the hole before it. `HoleTimeline.possibleHoles(at:)` gives the holes a moment can be on: the hole the timeline says, and every hole after it up to the next one that has a start. A hole is shown the stops and fixes whose possible holes include it, filtered by the hole's own shape as before. Once its first stroke is added, the window narrows to the real one.

### Live Activity and score

The Live Activity shows the display hole. "To par" leaves out the display hole of an active round, as it left out the current hole before.

## Not in this change

- The display lock, and moving the display from any tee rather than only the next hole (see the 2026-10-03 cases).
- Removing a stroke never changes the timeline.
