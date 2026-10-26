# Edit club distances

The Golf Bag screen gets a **Distances** button at the top that opens a screen to edit how far the player hits each club. Follows plans/2026-10-10-club-distances.md, which stored the distances but did not show them.

## Decisions

| Topic | Decision |
|---|---|
| Button | `Distances`, a link in the Golf Bag screen's navigation bar, top right |
| Screen | `ClubDistancesView`, titled "Club Distances". One row per club in the bag, in bag order: club name, a number field, "yd" |
| Field | A number field in a shaded box, so it looks editable. It empties when it gets focus and shows the saved distance as its placeholder, so typing replaces the distance |
| Putter | Left out; it has no distance |
| Range | Whole yards, 1 to 400. Anything else (empty, 0, over 400) goes back to the saved distance |
| When saved | When a field loses focus (another field, or the Done button at the top right, shown while a field is being edited) and when the screen closes. Not on each key, so iCloud gets one change per edit |
| Store | `GolfBagStore.setDistance(_:for:)`, which already exists |
| Club taken out and put back | Starts at its default, as before |

## Tests

| Test | Checks |
|---|---|
| `GolfBagUITests.testEditDistance` | The Distances button opens the screen, the driver shows 230, the putter has no row, a new driver distance is still there after leaving and coming back |
