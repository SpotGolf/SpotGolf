# Shotgun start

A round can start on any hole of the selected nines and plays round to the hole before it. The Bear Dance round of 2026-10-13 started on hole 9: the watch never moved from the 18th to the 1st, and the phone's hole timeline could not place holes 1 to 8 (see `2026-10-16-bear-dance-putt-analysis.md`).

## 1. Choosing it

The nines screen gets **Starting hole**, a stepper from 1 to the number of holes in the selected nines (9 or 18), default 1. Changing the nines keeps it in range. A course with one nine skips the nines screen and starts on hole 1.

## 2. Play order

`CourseSelection` gets `startHoleIndex`, optional, the 0-based position in nine order of the first hole played. Nil is hole 1, so saved rounds and selections without it decode and encode as before.

`orderedHoles` and every lookup built on it are in play order: nine order rotated to start at the starting hole. Index `i` is the `i`-th hole played. Everything that walks indices upward then works unchanged:

| Where | Why it needs no change |
|---|---|
| `HoleAdvancer` | Advances to index + 1 and stops at the last index, which is now the hole before the starting hole |
| `HoleTimeline` | "The hole only goes up" holds in play order |
| Watch Next arrow, `lastHoleIndex` | Last index is the last hole played |
| Pins, strokes, stats | Stored by play index. Shared pins use `holeKey`, the nine's name and hole number, so they match across phones |

## 3. Hole numbers

A hole's number is its place in nine order: `CourseSelection.holeNumber(at:)`, with `playIndex(ofHoleNumber:)` back.

| Where | Shows |
|---|---|
| `Round.displayHoleNumber` (watch title, Putt Lab, Live Activity) | The hole's number |
| Hole header circles on the phone | Play order, labeled with numbers |
| Hole timeline sheet | The number |
| Scorecard | Nine order, 1 to 18, Out and In as today |
| CSV export | The hole's number; import maps it back through the selection |
| `ContactMonitor` (contactsOn value, Putt Lab segment hole) | The number |

## 4. Compatibility

The phone and watch must run the same version to start a round, so `StartRound` carries the field in the course data with no other change. An older build reading a shotgun round's saved course would play it from hole 1. `feat`, MINOR.

## Checks

1. `CourseSelection`: rotation for one and two nines, numbers and indexes both ways, `holeKey` unchanged, clamping, decoding without the field, `trimmed` keeps it.
2. `HoleAdvancer`: a round started on 9 of 18 advances from the 18th to the 1st and stops after the 8th.
3. `Round`: display hole number and a timeline that runs 9 to 18 to 1.
4. Export and import of a shotgun round keep each stroke on its hole.
5. The stepper on the nines screen in the simulator.
