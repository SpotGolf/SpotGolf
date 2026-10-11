# Penalty strokes and shot quality

Each stroke counts the penalty strokes it cost, 0 to 4, set with a counter in the Edit Spot sheet, and carries the player's rating of the shot. This replaces the Penalty stroke and Out of bounds buttons from plans/penalties.md.

## Decisions

| Topic | Decision |
|---|---|
| Out of bounds | Dropped. A spot is where the ball was hit from, so an out of bounds spot held nothing a penalty spot does not. A ball out of bounds or lost is a penalty stroke hit from the same place as the stroke before it |
| Counter | Under the club grid, on the left: a "Penalty strokes" label over `[−] N [+]`. Starts at 0 for a new spot, at most 4. Minus is disabled at 0 and plus at 4. Save applies it with the club, the quality and the order; Cancel drops it |
| Shot quality | On the right of the same row: a "Shot quality" label over a pill with three segments, thumbs down, a neutral face and thumbs up, as flat outline icons. A new spot is a good shot; tapping a segment selects it, and a rating cannot be cleared. Not used yet; kept for statistics |
| Score | A stroke scores 1 plus its penalty strokes. The hole, the round, the score box, the scorecard and the round list add them up |
| Stats | A stroke with penalty strokes is not a putt, does not hit the fairway, and counts its penalty strokes toward reaching the green |
| Pins | Red with one or more penalty strokes, blue otherwise. The white out of bounds pin is gone |

## Model

- `Stroke.penaltyStrokes: Int`, replacing `StrokeType`. `Stroke.maxPenaltyStrokes` is 4. `score` is 1 plus the penalty strokes.
- `Stroke.quality: ShotQuality`, one of `unrated`, `bad`, `okay` or `good`. New strokes are `good`. `RoundStore.setShotQuality(_:strokeID:in:)` sets it.
- `RoundStore.setPenaltyStrokes(_:strokeID:in:)` keeps the count between 0 and the most.
- `SpotSelection.penaltyStrokes` and `quality` are the sheet's values.

## Compatibility

- A stroke saved with a `type` and no `penaltyStrokes` decodes `penalty` and `outOfBounds` as 1 and `regular` as 0. A stroke saved or exported without a `quality` is unrated, and shows no selection.
- The CSV export's `strokeType` column holds the penalty strokes as a number, and a `quality` column after `club` holds the rating. The importer also reads the old words and the header without `quality`.
- Older builds cannot read strokes without a `type`, so this is a breaking change: MINOR, per CLAUDE.md.

## Tests

- `StrokeTests`: the default is 0, the count round-trips, old JSON decodes, and `score` adds the count. The quality round-trips and old JSON is unrated.
- `RoundStoreTests`: `setPenaltyStrokes` sets and clamps the count, `setShotQuality` sets the rating, and `moveStroke` keeps both.
- `HoleTests`, `RoundTests`, `HoleOverviewTests`, `HoleStatsTests`: scores and stats with penalty strokes.
- `TrackExporterTests` and `TrackImporterTests`: both columns round-trip, and the old words and headers import.
- `PenaltyFlowUITests`, `ClubSelectionUITests`, `PastRoundUITests`: the counter adds, removes, stops at 0 and 4, and survives Save. A quality is selected, swapped, cannot be cleared, and survives Save.
