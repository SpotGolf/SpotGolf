# Full-swing strokes

Rules for `StrokeFinder.suggestions`, from the Coal Creek round of 2026-10-02 (`Data/coal-creek-2026-10-02.csv`), the first round recorded with the watch's 3 g swing threshold. The player's notes for holes 1 to 4 were compared with the GPS and swings stop by stop.

## Problem

The watch recorded 698 swings; 622 were under 10 g. The rules of 2026-09-29 treated every swing in a stop as a possible stroke and kept the last one in each stop. That gave 132 swing suggestions for about 57 full swings:

| Cause | Example |
|---|---|
| The last swing in a stop wins, so a 3 to 6 g fidget after the shot replaces it | Hole 1: the 18 g drive at 08:07:46 shown as a 4 g swing 52 s later |
| Waiting at the tee makes fidget stops that escape the 90 s practice window | Hole 2: 7 minutes at the tee gave 4 tee shots for 1 |
| 3 to 5 g swings in walking pauses, and while watching others, become strokes | Hole 3: 3 false strokes down the fairway |
| A swing near a forward tee box merges with the drive and moves it | Hole 4: the drive placed 63 m down the hole |
| "A new stop must be closer to the green" drops real shots | Hole 4: a 24 g chunk 1 m from the previous stop |
| The cap of 10 cuts the putts | Holes 3, 4, 12 and 15 |

## Evidence

| Swings on holes 1 to 4 | Peak g |
|---|---|
| Confirmed full shots (14) | 13, 14, 18, 18, 18, 20, 21, 23, 24, 24, 24, 25, 26, 28 |
| Practice swings and other strong movements around a shot | 9, 10, 10, 10, 13, 18 |
| False strokes in the fairway | 3 to 5 |
| On the greens, for 2 putts each | 9 to 13 swings of 3 to 7 g |

Pairs of strong swings at one spot: within 13 s they were practice then the shot (5 of 5). 42 s and 7 m apart they were two shots (a bunker shot, then a chunk).

One full swing had no strong peak: the hole 4 six iron, at best 8.6 g at 09:00:04.256 with a 4.0 g swing 3.1 s later. The watch kept only the peak of the first 0.5 s of a swing and ignored readings for 3 s after its start, so a waggle that starts the swing hides the real swing behind it.

## Rules

| | Rule | Constant |
|---|---|---|
| 1 | A swing of 10 g or more made in a stop is a full swing, and a stroke anywhere on the hole | `fullSwingPeak` |
| 2 | Full swings within 60 s and 15 m of the previous one are one stroke, the strongest: practice swings and the shot. A duff hit again from the same spot within a minute is lost, and the player adds it by hand | `sameShotWindow`, `sameShotRadius` |
| 3 | A full swing's position is the GPS fix at the swing, and its time is the swing's. Its ID comes from the first swing at the spot, which does not change as more arrive | |
| 4 | Softer swings count only on the green or within 30 m of its edge, where the strongest in a stop is the putt. Stops with no swing there are offered as before. No "closer to the green" rule | `chipZoneMargin` |
| 5 | Full swings are never cut by the cap of 10; putts and chips fill the rest in time order | `maxPerHole` |
| 6 | Watch: a swing's peak is the highest reading in the 3 s after its start, not in the first 0.5 s | `SwingPeakFinder.cooldown` |

Kept: a swing must fall in a stop (8 s within 5 m); a stop more than 60 m from the centerline is off the hole unless it is at a tee.

Removed: the tee practice window, "the last swing in a stop wins", "a new stop must be closer to the green".

## Results

Full-swing strokes per hole on Coal Creek, against the player's notes where they exist:

| Hole | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Found | 2 | 3 | 3 | 5 | 3 | 3 | 2 | 4 | 5 | 3 | 3 | 4 | 2 | 3 | 3 | 2 | 2 | 5 |
| Notes | 2 | 3 | 3 | 7 | | | | | | | | | | | | | | |

Hole 4 misses the six iron (no strong peak; rule 6 is for that) and merges the chunk into the bunker shot 42 s before it (rule 2). Suggestions per hole fall from 7 to 10 down to 4 to 9. The ones left are on the greens, which are the next piece of work.

Walnut Creek, recorded at the 10 g threshold, changes little: 6 6 6 3 3 3 1 5 4 4 3 2 4 1 3 3 2 4 full swings per hole against the scorecard's 4 4 5 3 3 3 2 4 4 4 3 2 4 1 4 3 3 3.

## Not in this change

- **Putts.** On a green the swings are 3 to 7 g, the same as the fidgets, and GPS cannot separate them: the green's stops form a chain 6 to 9 m apart, each starting a second after the last. The clean signals are the first swing after walking on and the last before walking off. The bag going down at the green's edge looks like a chip.
- **Penalties.** A stop beside water followed by a chip from the rough next to it is suggestive, not reliable.

## Files

| File | Change |
|---|---|
| `SpotGolf/Services/StrokeFinder.swift` | Rules 1 to 5 |
| `Shared/Models/StrokeSuggestion.swift` | `id(forStopAt:)` becomes `id(at:)`, because a full swing's ID comes from a swing time |
| `SpotGolfWatch/Utilities/SwingPeakFinder.swift` | Rule 6. `peakWindow` and the separate cooldown bookkeeping go |
| `SpotGolfTests/StrokeFinderSuggestionTests.swift`, `StrokeFinderRealRoundTests.swift`, `SpotGolfWatchTests/SwingPeakFinderTests.swift` | The new rules. Coal Creek joins Walnut Creek as a real round |
