# Advance the hole when the player leaves the green

## Problem

The watch moves to the next hole only once the player stands inside one of that hole's tee boxes (`HoleAdvancer.detectHole`). Players finish putting, walk to the bag, wait for the group ahead, and only then step onto the tee. So the hole changes late.

On the Flatirons round of 2026-10-01 (`Data/flatirons-2026-10-01.csv`), the player entered every next tee box. The change still came 17 s to about 2.5 min after the player left the green.

## Rule

Advance from hole N to hole N+1 when **either** rule fires, whichever comes first.

| Rule | Fires when |
|---|---|
| Tee box (current) | A fix is inside one of hole N+1's tee boxes. |
| Green exit (new) | All of the following are true: (1) hole N's green is no more than `maxGreenToTee` (100 m) from hole N+1's nearest tee box; (2) since hole N started, at least `minGreenFixes` (20) fixes were inside hole N's green, counted in total, not in a row; (3) the current fix is at least `greenExitDistance` (20 m) from the green's edge; (4) the distance to hole N+1's nearest tee box shrank by at least `towardTeeDistance` (5 m) over the last `towardTeeWindow` (10 s). |

Why each part of the green-exit rule is there:

1. **Within 100 m:** without it, the rule fired at the end of a 9-hole round. The walk toward the clubhouse went toward the 10th tee, which is 170 m from the 9th green. On longer gaps the tee-box rule still works.
2. **20 fixes on the green (about 20 s):** walking toward the green, cutting across a corner of it, or GPS drift onto it doesn't count. See "Fixes on the green" below for the numbers.
3. **20 m away:** this is beyond where players usually leave a bag or cart next to the green, so walking to the bag mid-hole doesn't count. At 25 m or 30 m the rule fired on fewer holes, with no fewer early fires (there were none at any distance).
4. **Heading to the tee:** walking off the green in another direction, for example back to the fairway, doesn't count.

Simulated on the Flatirons round, with the times at which each rule fires (minutes into the round):

| Hole | Left green | Tee-box rule | Green-exit rule |
|---|---|---|---|
| 1→2 | 25.8 | 26.4 | 26.0 |
| 2→3 | 39.9 | 42.4 | 40.1 |
| 3→4 | 56.3 | 56.5 | — (tee 14 m from green) |
| 4→5 | 68.8 | 69.9 | 69.9 |
| 5→6 | 82.8 | 84.7 | 83.2 |
| 6→7 | 99.6 | 100.5 | 99.8 |
| 7→8 | 117.9 | 119.1 | 118.3 |
| 8→9 | 128.3 | 130.5 | 129.4 |
| 9→10 | 143.2 | never | — (tee 170 m away) |

The green-exit rule never fired before the player's last fix on the green.

### All recorded rounds

Simulated on the three recorded rounds, using the full rule with 20 fixes on the green: Flatirons 2026-10-01, Walnut Creek 2026-09-25 and Cherry Hills 2026-09-22.

| | Result |
|---|---|
| Hole changes | 35 |
| Changed by the green-exit rule | 26 |
| Changed before the player's last fix on the green | 0 |
| Average time saved over the tee-box rule | 83 s |

### Fixes on the green

Fixes arrive about once a second. Across the 35 holes:

| Measure | Fewest | Next fewest |
|---|---|---|
| Total fixes inside the green on a hole | 31 (Walnut Creek 16) | 47 (Walnut Creek 10) |
| Longest run of fixes inside the green in a row | 21 (Walnut Creek 7) | 26 (Walnut Creek 16) |

- 19 of the 35 holes also had short visits to the green: 1 to 19 fixes, from GPS drift at the edge or walking across it.
- A minimum anywhere from 1 to 30 gave the same results on these rounds. A minimum of 40 missed one hole.
- **20 in total** sits below the fewest seen (31), so a quick hole-out still counts. It is above most short visits, and it guards against cases these rounds didn't include.
- **Total, not in a row:** counting in a row would have needed 21 or fewer to work on Walnut Creek 7, because GPS drift splits a stay on the green into several visits.

## Design

`HoleAdvancer` becomes stateful, because the new rule needs recent fixes and a count of fixes on the green.

```swift
struct HoleAdvancer {
    static let greenExitDistance: CLLocationDistance = 20
    static let towardTeeDistance: CLLocationDistance = 5
    static let towardTeeWindow: TimeInterval = 10
    static let maxGreenToTee: CLLocationDistance = 100
    static let minGreenFixes = 20

    private(set) var isPaused = false
    // The hole the state below is for; a change of hole clears it
    private var holeIndex: Int?
    // Fixes inside the current hole's green since the hole started
    private var greenFixes = 0
    // Recent fixes with their distance to the next tee, oldest first, at most towardTeeWindow long
    private var recent: [(timestamp: Date, toTee: CLLocationDistance)] = []

    /// Returns the next hole index when either rule fires for this fix.
    mutating func advance(location: CLLocation, courseSelection: CourseSelection, currentHoleIndex: Int) -> Int?
}
```

- The hole shapes come from `StrokeFinder.HoleShape`, which already measures distance to greens and tees, so both rules use the same geometry as the phone's hole-start fixing.
- The state resets when `currentHoleIndex` changes, including when the user picks a hole by hand or the phone's timeline moves it.
- `pause()` and `resume()` keep working as now.

### Callers

| Caller | Change |
|---|---|
| `WatchAppDelegate.advanceHole` | Keeps a `HoleAdvancer`. Feeds it **every** fix in each batch, not only the last one, so the 10 s window is complete. `WatchHoleAdvance` keeps its pause flag. |
| `RoundMapView` (phone) | Calls `holeAdvancer.advance(...)` in place of `HoleAdvancer.detectHole(...)`. |

`detectHole` is removed; the tee-box check moves inside `advance`.

The phone's `StrokeFinder.holeStarts` already sets hole starts after the round from the last fix on the previous green. So a live advance that is a little early or late is still fixed on the phone.

## Tests

- **Unit tests (`HoleAdvancerTests`) with a small synthetic hole:**
  - the tee-box rule still fires
  - the green-exit rule fires after being on the green, then moving 20 m away and 5 m closer to the tee
  - it doesn't fire with fewer than 20 fixes on the green
  - it does fire after 20 fixes on the green split across several visits
  - it doesn't fire within 20 m of the green
  - it doesn't fire when walking away from the tee
  - it doesn't fire when the tee is over 100 m from the green
  - the state resets when the hole changes
- **Real-round test (`HoleAdvancerRealRoundTests`):** like `StrokeFinderRealRoundTests`, read the 2026-10-01 track from the git-ignored `Data` folder and the course from the sibling CourseData checkout, and skip when either is missing. Replay the track through `advance`. Check that holes 1→9 each advance no earlier than the last fix on the green and no later than the tee-box rule, and that the round never advances to hole 10.
