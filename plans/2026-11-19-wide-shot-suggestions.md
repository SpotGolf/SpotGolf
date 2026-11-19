# Wide shots are suggested

Branch: `fix/wide-shot-suggestions`. Phone only. Nothing new is stored, and the watch does not change.

## Problem

Walnut Creek, 2026-11-17 (`Data/Simulations/walnut-creek-golf-preserve-2026-11-17`). Two full swings were recorded by the watch and never suggested:

| Hole | Club | Peak | From the hole's centerline | Nearest other hole |
|---|---|---|---|---|
| 12 | 6 iron | 23.3 g | 62 m | Hole 16, 27 m |
| 15 | 5 iron | 27.5 g | 60.4 m | Hole 13, 48 m |

`StrokeFinder` drops a full swing made in a stop more than 60 m from the centerline (`maxCenterlineDistance`), unless it is within 10 m of a tee box. The rule is there for the turn, the range and the parking lot. It also drops a shot hit from another fairway.

## Evidence

Full swings more than 60 m from the centerline, in the Walnut Creek round and the Broadlands round of 2026-10-26:

| Swing | From the centerline | When |
|---|---|---|
| Hole 12 six iron | 62 m | After the tee shot, before the green |
| Hole 15 five iron | 60 m | After the tee shot, before the green |
| Practice swing on the next tee, after hole 10 | 95 m | After the green |
| Swing after hole 5 (Front 5) | 145 m | After the green |
| Swing at the turn, after hole 18 | 177 m | After the green |
| Four swings after the Broadlands round | 210 m | After the green |

Distance alone cannot tell them apart safely: 62 m is a shot and 95 m is not. When they happened can.

## Idea

Golf is linear. The player enters a hole at its tee, plays it, and leaves it going forward to the next hole. Any full swing made in a stop between entering and leaving is on the hole, however far from the centerline. Outside that time the 60 m rule stays.

```
previous green ── gap ── ENTER ───── every full swing kept ───── EXIT ── gap ── next hole
                 60 m    (tee)                                  (green,   60 m
                 rule                                            past it,  rule
                                                                 or next tee)
```

## Rules

All of these are worked out from the stops the hole timeline already offers the hole (`possibleHoles`), each time suggestions are worked out. The display hole is not used.

| | Rule | Constant |
|---|---|---|
| 1 | **Enter:** the first stop within 10 m of one of the hole's tee boxes. Until a full swing is made at the tee, a later stop at the previous hole's green (on it or within the green zone) undoes it, and the next stop at the tee enters again. After the tee shot nothing undoes it, so a topped drive that stops beside the previous green stays on the hole | `teeShotRadius` (existing), `zoneMargin` (existing) |
| 2 | **Exit:** the first stop after entering that is one of: | |
| 2a | at the green: on it or within the green zone | `zoneMargin` |
| 2b | past the green: the nearest point of the centerline is its end at the green, and the stop is outside the green zone | |
| 2c | at the next tee: within 10 m of a tee box of the next hole in playing order | `teeShotRadius` |
| 3 | A full swing in a stop from the entering stop up to, but not including, the exit stop skips the 60 m rule | |
| 4 | Every other stop keeps today's rule: more than 60 m from the centerline is off the hole, unless at a tee | `maxCenterlineDistance` (existing) |
| 5 | Putts, contacts and stops near the green do not change | |

Why each exit sign:

| Sign | Covers |
|---|---|
| 2a | The normal hole. No wide shot comes after reaching the green |
| 2b | A holed approach or chip, or a ball thrown back by another player: the player never goes to the green and walks on past it |
| 2c | The same, where the next tee is beside or behind the hole, so the player never passes the green |

Why rule 1 waits for the last stop at the previous green: a player can leave a push cart at the next tee and walk back to putt. That happened on Walnut Creek hole 7 (a stop at hole 8's tee 98 s before the first stop at hole 7's green). Going back to the green means the player has not moved on, so the next hole is not entered until they come back to its tee. During play this corrects itself, because suggestions are worked out fresh each time.

Missing shapes:

| Missing | Effect |
|---|---|
| Tee boxes | The hole is never entered: today's rule everywhere |
| Centerline | No 60 m rule today, and none now. Sign 2b cannot fire |
| Green | Signs 2a cannot fire; 2b uses the centerline's end alone |
| Next hole (last hole of the round) | Sign 2c cannot fire |
| Previous hole (first hole) | Enter at the first stop at the tee |

## Decisions I made that you have not confirmed

| | Decision | Other choice |
|---|---|---|
| A | In the gap between one hole's exit and the next hole's entry, the 60 m rule stays, so a chip from over the green still shows | Never show full swings in the gap |
| B | After a cart stop at the next tee closes the hole, a later shot on it from more than 60 m wide is dropped | Reopen the hole when the player stops on it again |
| C | No outer limit inside the hole. On the last hole, or the ninth before the turn, with the green skipped and the clubhouse not past the green, a full swing at the clubhouse would be suggested | Also close the hole when a stop is more than about 150 m from the centerline |

## Known weak points

| Case | What happens |
|---|---|
| A shot from level with or beyond the green, more than 60 m to the side | Sign 2b closes the hole first; the shot is dropped and added by hand |
| A wide ball that stops the player within 10 m of the next hole's tee | Sign 2c closes the hole; later wide shots fall under the 60 m rule |
| The player never stops at the hole's tee (tee swing made while GPS was still moving) | The hole is never entered: today's rule |

## Checked against the two rounds

A Python replay of the exit rules over all 27 holes (entry taken as the tee shot):

| Check | Result |
|---|---|
| Hole 12 and hole 15 wide shots | Both kept |
| Off-hole swings (95, 145, 177 and 210 m) | All dropped |
| Holes where 2b or 2c fired, so the hole would close with the green skipped | 27 of 27 |
| 2b before 2a | 3 holes: over the green, chip back. The chip is within 60 m, so kept |
| 2c before 2a | 1 hole: the cart stop on Walnut Creek hole 7. The shot after it was 20 m off, so kept |

Neither round has a hole played without going to the green. That case is covered by tests with made-up tracks only.

## Code

| File | Change |
|---|---|
| `SpotGolf/Services/StrokeFinder.swift` | `suggestions(on:…)` takes two more shapes: `previous: HoleShape?` and `next: HoleShape?`. A private `window(…)` returns the indexes of the entering and exit stops among the offered stops. The centerline check in the swing loop is skipped for a stop inside the window. `suggestions(in:holeIndex:…)` builds the two shapes from the holes before and after `holeIndex` in playing order. Doc comments updated |
| `Shared/Utilities/HoleShape.swift` | `isPastGreen(_:)`: true when the nearest point of the centerline to a point is the centerline's last point |
| `Shared/Utilities/LocalDistance.swift` | A polyline helper that also says whether the nearest point is the line's last point, used by `isPastGreen` |
| `SpotGolf/Views/RoundMap/RoundMapView.swift` | No change: it calls `suggestions(in:holeIndex:…)` |
| `plans/2026-10-04-full-swing-strokes.md` | One line under "Kept" pointing here |

## Tests

New cases in the `StrokeFinder` tests, each with a made-up hole (tee, centerline, green) and track:

| # | Case | Expect |
|---|---|---|
| 1 | Tee shot, then a full swing in a stop 100 m off the centerline, then the green | Suggested |
| 2 | The same swing after a stop at the green | Not suggested |
| 3 | Green skipped: full swing 100 m off after a stop past the green | Not suggested |
| 4 | Green skipped: full swing 100 m off after a stop at the next hole's tee beside the fairway | Not suggested |
| 5 | Full swing 100 m off before any stop at the tee | Not suggested |
| 6 | Cart stop at the next tee, back to the green, a knock on that green of 10 g or more: shown hole is the next hole | Not suggested on the next hole |
| 7 | Chip from 20 m over the green after sign 2b | Suggested (within 60 m) |
| 8 | Hole with no tee boxes, swing 100 m off | Not suggested |
| 9 | Last hole: no next shape, wide shot before the green | Suggested |
| 10 | Existing tests | Pass unchanged |

After the code, the real `StrokeFinder` was run over the Walnut Creek export's fixes, swings and hole starts in a temporary test (not kept):

| Check | Result |
|---|---|
| Hole 12 six iron (2552 s, 62 m) | Suggested |
| Hole 15 five iron (5131 s, 61 m) | Suggested |
| Other full swings more than 60 m from the centerline | One, hole 13 at 3753 s: its stop is 58 m off, so it was suggested before too |
| New false full swings | None |

It was not replayed on simulators with `Scripts/replay-round.py`.

## Steps

1. `LocalDistance` helper and `HoleShape.isPastGreen`, with tests.
2. `StrokeFinder.window` and the skipped centerline check, with tests 1 to 9.
3. Pass the previous and next shapes from `suggestions(in:holeIndex:…)`.
4. Run the `StrokeFinder` tests (`StrokeFinderSuggestionTests`, `StrokeFinderRealRoundTests`).
5. Run the real `StrokeFinder` over the Walnut Creek export and check holes 12 and 15.

## Not in this change

- The 15 putts added by hand in the Walnut Creek round.
- Three 58° chips near the greens of holes 10 and 16 that were added by hand. Their cause has not been looked at.
