# Club selection

Each stroke records the club it was hit with. When a spot is created, the app guesses the club from the hole and the spot's location, and the Edit Spot sheet shows the bag with the guess selected. The player changes it with one tap, and never has to scroll to see the bag. Follows plans/2026-10-10-club-distances.md.

## Decisions

| Topic | Decision |
|---|---|
| Where the club is picked | In the Edit Spot sheet, the one sheet for a spot. There is no club sheet of its own |
| When the sheet opens | On both ways of creating a spot: a long press on the map, as now, and tapping a suggestion pin, which today adds the stroke with no sheet |
| Pre-selection | The stroke's club, or the guess for a stroke without one (old rounds). One club is always selected while the bag has a club to offer |
| Changing the club | Tapping a club selects it and nothing else. The sheet's buttons stay as they are: Save, Cancel, the penalty buttons, Delete Spot |
| What saves the club | Save, like the spot's order. Penalty stroke, Out of bounds and Clear penalty also save it, since they close the sheet. Cancel leaves the club the stroke had, which for a new spot is the guess |
| Penalty strokes | Keep their club. The spot was hit with it |
| Watch | Nothing changes. The watch decodes the field with the strokes snapshot and ignores it. Older watch builds ignore the unknown key |
| Live Activity, scorecard, hole stats | No change |

## Guess

`Shared/Utilities/ClubGuess.swift`, `enum ClubGuess`, pure and tested:

```swift
static func club(in bag: GolfBag, yardsToTarget: Int?, isOnGreen: Bool, isTeeShot: Bool) -> Club?
```

| | Rule |
|---|---|
| 1 | On the green: the putter, when the bag has one |
| 2 | The candidates are the bag's clubs with a distance. Off the tee the driver is left out: it is a tee club, and a shot beyond the fairway woods gets the longest of them |
| 3 | Without yards to the target (the hole has no green in the course data): a tee shot gets the longest candidate, any other stroke gets no guess |
| 4 | The candidate whose distance is nearest the yards. A tie goes to the longer club. Beyond the longest candidate's distance that is the longest; inside the shortest's it is the shortest, so chips get the shortest wedge |
| 5 | No candidates: nothing, and the sheet selects nothing |

The phone works out the inputs where a spot is created, from `Round`: yards from the spot to `targetCoordinate(holeIndex:)` (the pin, or the green's center), `isOnGreen(_:holeIndex:)`, and whether the stroke is the hole's first. `HoleOverview.guessedClub(_:holeIndex:strokeIndex:at:bag:)` does that, so the two creating paths and the sheet share it.

## Model

`Shared/Models/Stroke.swift`:

| Change | Detail |
|---|---|
| `var clubID: String?` | `Club.id`. Nil for strokes from before this change, and when the bag offered nothing. `Codable` is synthesized, so old saved rounds and old snapshots decode with nil |
| `var club: Club?` | `Club.named(clubID)` |
| `init(id:coordinate:type:club:)` | `club` defaults to nil |

`Shared/Services/RoundStore.swift`:

| Change | Detail |
|---|---|
| `setStrokeClub(strokeID:club:in:)` | Like `setStrokeType`. Goes through `changeStrokes`, so the watch gets the snapshot |
| `moveStroke` | Keeps the club. Today it rebuilds the stroke with only its ID and type |

The CSV export gains a `club` column at the end of the header, filled only on stroke rows. The importer reads it, and still reads the two older headers.

## Phone

| File | Change |
|---|---|
| `RoundMapLayer.swift` | The long press makes the stroke with the guessed club. The suggestion pin's tap, after `addSuggestedStroke`, sets `spot` to the new stroke and its index, which opens the sheet |
| `RoundStore+Suggestions.swift` | `addSuggestedStroke` takes the club and puts it on the stroke |
| `RoundMapState.swift` | `SpotSelection` gains `club: Club?`, the selection shown in the sheet |
| `SpotEditSheet.swift` | A club grid under the Spot stepper: the bag's clubs in `Club.all` order, plus the stroke's club when the bag no longer has it. The selected club's button is filled, like the Golf Bag screen, and the others bordered. When the sheet appears, `spot.club` is the stroke's club or the guess. Tapping sets `spot.club`. Save and the penalty buttons call `setStrokeClub` when the club differs from the stroke's. The sheet's detents become medium and large; the grid sits above the fold at medium |

The grid is `ClubGrid`, a view the Golf Bag screen uses too. Buttons are 44 points high with the club's short name, identifier `Club-<id>`, label the club's name, `isSelected` trait when selected. Up to 14 clubs fit in three rows at phone width, so nothing scrolls.

## Tests

- `ClubGuessTests`: the putter on the green; the driver for a long tee shot and the 3 wood for a long second shot; the nearest club by yards, with the tie to the longer club; the shortest wedge for a chip; the tee shot without yards; an empty bag.
- `StrokeTests`: a stroke decodes from JSON without `clubID`, and the club round-trips.
- `RoundStoreTests`: `setStrokeClub` changes the club, and `moveStroke` keeps it.
- `TrackExporterTests` and `TrackImporterTests`: the club column round-trips, and the old headers still import.
- `PenaltyFlowUITests` or a new `ClubSelectionUITests`: a long press opens Edit Spot with a club selected; tapping another club and Save keeps it, shown when the spot is opened again; a penalty stroke keeps its club.

## Versioning

`feat`, so MINOR. Not breaking: older builds ignore the new key.
