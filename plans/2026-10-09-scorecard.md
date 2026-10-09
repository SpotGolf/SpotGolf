# Scorecard

The score box at the top right of the map opens a scorecard for the round.

## Tee box

A round saves the tee the player picked when starting it.

- `CourseSelection.teeName: String?`. Nil for rounds started before this change. The watch gets it with the course, and older builds ignore it.
- The tees offered are the course's tees, then its combo tees. A combo tee's yards on a hole come from the tee named in `Hole.comboTees`.
- `CourseSelectionView` gets a "Select Tee" step after the nines (or straight after the course when it has one nine). Each row shows the tee's color and its yards over the chosen holes. A course with no tees skips the step.

## Stats

Worked out from the strokes and the course shapes, and saved on each hole as `RoundHole.stats` (`HoleStats`). `RoundStore` saves them again on every stroke change: adding, moving, reordering, removing, or changing a stroke's type in edit mode, and strokes from the phone arriving on the watch. The importer saves them for an imported round. Rounds saved before this change get them once when the store loads. The scorecard only reads them.

| Stat | Rule |
|---|---|
| Score | Every stroke on the hole, penalty marks included |
| Putts | Regular strokes inside the hole's green |
| Fairway | Par 4 and 5 only. The second stroke is regular and inside one of the hole's fairways or its green |
| Green | The first regular stroke inside the green is stroke number par − 1 or sooner. A hole holed from off the green misses, since it looks the same as a hole still being played |

Score is the hole's stroke count. A hole with no strokes shows nothing. Each played hole of an active round shows its stats so far, the display hole included.

## Layout

```
┌──────────────────────────────────────────┐
│ Course name                     ┌──────┐ │
│ Gold Tees · Oct 9, 2026         │ 82 +10│ │
│                                 └──────┘ │
├──────┬─────────────────────────┬─────────┤
│ Hole │ 1 2 3 … 9 Out 10 … 18 In│   Tot   │
│ Yards│      scrolls sideways   │  fixed  │
│ Par  │                         │         │
│ Score│                         │         │
│ Putts│                         │         │
│ Fair.│                         │         │
│ Green│                         │         │
│ Edit │                         │         │
├──────┴─────────────────────────┴─────────┤
│              [   Close   ]               │
└──────────────────────────────────────────┘
```

- The row titles and the total column stay put. The hole columns between them scroll sideways.
- Holes are a fixed width, so landscape shows more of them.
- "Out" follows hole 9 and "In" follows hole 18. A 9-hole round has no "In" column.
- Fairway and Green show a check on a hit. Their subtotal and total columns show hits over chances, like `5/7`.
- The Yards row only shows when the round has a tee.
- Edit on a hole closes the scorecard and opens the map's edit mode on that hole.
