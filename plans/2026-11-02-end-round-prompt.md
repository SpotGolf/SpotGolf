# End Round Prompt

## Problem

Players forget to end the round. The workout, GPS and sensors keep running on the watch, which drains its battery, and the round's GPS track goes on to the parking lot. Rounds can be edited after they end, so ending a little early costs little.

## Decision

The watch asks the player to end the round 5 minutes after they leave the final green. If they don't answer, the round ends by itself 20 minutes after that. Either way, the round's end time is the player's last GPS fix on the final green.

- Only the watch asks. The phone gets no notification.
- The final hole is the last hole in play order, so shotgun starts are covered. It is found by GPS alone: no strokes, and not the display hole.
- No prompt after a long stop on other holes. A round quit early still needs End Round.

## Real round

Broadlands, 2026-10-26, front nine (`Data/Simulations/broadlands-golf-course-2026-10-26`). Simulated over the whole round, from the start:

| Event | Time into round |
|---|---|
| Last putt on hole 9 | 1:55:23 |
| Last fix on the hole 9 green (the end time this spec uses) | 1:55:35 |
| First fix ≥ 20 m from the green, after 51 fixes on it | 1:56:06 |
| Prompt | 2:01:07 |
| Player ended the round themself | 2:01:30 |

- The trigger fired only once, after hole 9. No visit to the hole 9 green earlier in the round counted.
- The watch detected 12 swings during the walk to the car, the first 25 s after leaving the green. So swings do not restart the wait. Only walking back onto the green restarts it.

## Design

```
watching ──[≥ 20 fixes on the final green, then a fix ≥ 20 m from its edge]──▶ left
left     ──[fix back on the green]───────────────────────────────────────────▶ watching
left     ──[5 min]───────────────────────────────────────────────────────────▶ asking: haptic and prompt
asking   ──[fix back on the green: prompt closes]────────────────────────────▶ watching
asking   ──[End Round]───────────────────────────────────────────────────────▶ ended at the last fix on the green
asking   ──[20 min, no answer]───────────────────────────────────────────────▶ ended at the last fix on the green
asking   ──[Keep Playing]────────────────────────────────────────────────────▶ done: no more asking this round
```

### `GreenExit` (watch, new)

The green-exit part of `HoleAdvancer`, moved into its own type so both features use it.

- Holds one hole's green (`HoleShape`), the count of fixes inside it, and the time of the last fix inside it.
- `exitDistance` = 20 m and `minGreenFixes` = 20 move here from `HoleAdvancer` (`greenExitDistance`, `minGreenFixes`), with their comments.
- `update(_ point:at:)` takes a fix and returns its distance from the green's edge, or nil when the hole has no green.
- `hasLeft`: at least `minGreenFixes` fixes inside the green, and the latest fix at least `exitDistance` from its edge.
- `lastOnGreenAt`: the time of the last fix inside the green.

`HoleAdvancer` keeps its next-tee checks (moving toward the tee, tee ≤ 100 m from the green, standing on the tee) and uses `GreenExit` for the rest. It still follows the display hole. Its behavior does not change.

### `RoundEndPrompter` (watch, new)

Decides when to ask and when to end. Pure logic, fed fixes and times, so tests drive it directly.

- Built for a round from `courseSelection.orderedHoles[lastHoleIndex]`, with a `GreenExit` for that hole. A final hole without a green never asks.
- Uses the fix's timestamp, not the clock, for every time below.

| Rule | Value |
|---|---|
| Ask after the player has left the green for | `promptDelay` = 5 min |
| End after asking, with no answer, after | `autoEndDelay` = 20 min |
| A fix back inside the green | Restarts the wait. If asking, closes the prompt and starts waiting again |
| Swings, strokes, display hole changes | Ignored |
| Keep Playing | Stops asking for the rest of this round |
| End time, for End Round and the automatic end | `GreenExit.lastOnGreenAt` |

- Changes are reported as `.ask`, `.stopAsking` (back on the green) and `.end(at: Date)`.
- State lives in memory only. A new round, a resumed round, or a relaunch of the watch app starts it over. After a relaunch, the player has to be on the final green again for it to ask.

### `WatchServices`

- Makes a `RoundEndPrompter` when a round becomes active, and drops it when the round ends.
- Feeds it each fix in `onRawLocations`, next to `advanceHole`.
- Also checks its deadlines every 30 s on a timer while a round is active, so they pass even when no fixes come in.
- On `.ask`: plays `.notification` through `SensorInputs.play` (every haptic goes through it), and sets the observed `asksToEndRound`, which the view shows. Logs `Round <id> asking to end: left the final green at <time>`.
- On `.stopAsking`: clears `asksToEndRound`.
- On `.end(at:)`: calls `watchSync.endRound(at:)`. Logs `Round <id> ended automatically, at the last fix on the final green (<time>)`.
- The prompt's End Round calls `watchSync.endRound(at: lastOnGreenAt)`. Keep Playing tells the prompter to stop asking.

### `WatchSync.endRound(at:)`

`endRound()` becomes `endRound(at date: Date = Date())`. An end time in the past first drops the records after it, as `endRequested` already does for the phone's end:

1. `streams.truncate(round.id, after: date)`
2. `end(round.id, at: date)`, which sets `lastSeq` and `endedAt`
3. Send `EndRound`, and queue its copy, as now.

Records sent to the phone before the truncate stay there. The phone already reads every stream only up to `endedAt`, and `receiveEndRound` keeps the watch's `endedAt`, so the phone needs no changes.

### Watch screen

`WatchRoundView` covers whichever page is open with the prompt while `asksToEndRound` is set. It is a view of its own, not an alert: a watchOS alert keeps its message at full size, and on a 45 mm watch that pushed Keep Playing off the screen.

| Part | Text |
|---|---|
| Title | End Round? |
| Message, in `.footnote` | You left the last green 5 minutes ago. The round ends by itself in 20 minutes. |
| Buttons | End Round (destructive), Keep Playing |

New strings go into `SpotGolfWatch/Localizable.xcstrings` by script, inserting only the new keys.

During a workout, raising the wrist goes back to the app, so the prompt is seen after the haptic. This is checked on the real watch (below).

## Steps

1. `GreenExit`, and `HoleAdvancer` moved onto it. Tests: `GreenExitTests` (fix count, 20 m, last time on the green, no green). `HoleAdvancerTests` and `HoleAdvancerRealRoundTests` pass unchanged.
2. `RoundEndPrompter`. Tests in `RoundEndPrompterTests`:
   - Asks 5 min after leaving, not before.
   - Fewer than 20 fixes on the green never asks.
   - Back on the green restarts the wait, and closes the prompt while asking.
   - Swings do not restart the wait.
   - Keep Playing stops asking for the round.
   - Ends 20 min after asking, at the last fix on the green.
   - Shotgun start: the final hole is the last in play order, not hole 18.
   - Final hole without a green never asks.
3. `RoundEndPrompterRealRoundTests`: the Broadlands export, skipped where `Data` is missing. Asks once, at 2:01:07, and ends at 1:55:35.
4. `WatchSync.endRound(at:)`. Tests: a past end time drops later records, sets `lastSeq` to the last record kept, and sends that `endedAt`. The phone's round keeps it.
5. `WatchServices` wiring, the 30 s timer, the haptic and the prompt. New watch strings.
6. Simulators: replay Broadlands on a clone pair with `replay-round.py --from 100 --to 125`. The prompt shows at about 121 min. Then check Keep Playing, End Round and the automatic end, each on its own replay.

## Check on real devices

On the next real round:

- The haptic is felt with the wrist down, and the prompt is on screen when the wrist is raised.
- In the log, the prompt comes about 5 min after the last putt on the final hole.
- The phone's round ends at the last fix on the final green, and its track stops there.
