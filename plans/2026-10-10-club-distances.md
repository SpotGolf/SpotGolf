# Club distances

Each club in the bag stores how far the player hits it. Today that is one number, the average distance for the club, so a later feature can pick a club for a stroke by distance. Later features will store more about each club: shortest, longest, average and weighted average from the player's own strokes, and how many strokes those come from. The bag moves from a settings string to SwiftData so those fields are plain additions. Follows plans/2026-10-10-golf-bag.md.

## Decisions

| Topic | Decision |
|---|---|
| Storage | A SwiftData model per carried club, in the apps' store next to `Round` and `LogEntry`. The bag is no longer `SettingsKey.bag` |
| Migration | None. The settings bag is not in any release (`0.7.0` is the last tag), so the key is simply dropped |
| Units | Yards, whole numbers, like every other distance in the app |
| Putter | Carried, but has no distance |
| Screens | None change. Editing distances came later: plans/2026-10-26-edit-club-distances.md |
| Watch | Nothing on the watch reads the bag. The model is in `Shared`, so the watch's store has the table, empty |

## Default distances

The average distance for an amateur golfer, in yards. A club gets its default when it is added to the bag.

| Club | Yards | Club | Yards | Club | Yards | Club | Yards |
|---|---|---|---|---|---|---|---|
| Dr | 230 | 2h | 200 | 1i | 205 | PW | 115 |
| 2w | 220 | 3h | 190 | 2i | 195 | AW | 105 |
| 3w | 215 | 4h | 180 | 3i | 185 | SW | 90 |
| 4w | 205 | 5h | 170 | 4i | 175 | LW | 75 |
| 5w | 200 | 6h | 160 | 5i | 165 | 46° | 115 |
| 6w | 190 | 7h | 150 | 6i | 155 | 48° | 110 |
| 7w | 185 | | | 7i | 145 | 50° | 105 |
| 8w | 175 | | | 8i | 135 | 52° | 100 |
| 9w | 170 | | | 9i | 125 | 54° | 95 |
| | | | | | | 56° | 90 |
| | | | | | | 58° | 85 |
| | | | | | | 60° | 75 |
| | | | | | | 62° | 65 |
| | | | | | | 64° | 55 |
| | | | | | | Pu | none |

## Model

`Shared/Models/Club.swift`:

| Change | Detail |
|---|---|
| `Club.defaultDistance: Int?` | The table above. Nil for the putter only |
| `GolfBag` | Stays the value views read: `clubs` in `Club.all` order, `capacity`, `isFull`, `contains(_:)`. Gains `distance(of:) -> Int?`. Loses `RawRepresentable`, `init(rawValue:)`, `rawValue` and `toggle(_:)`, which move to the store. `GolfBag.standard` stays as the seed: the standard 14 with their default distances |

`Shared/Models/CarriedClub.swift`, new:

```swift
@Model
final class CarriedClub {
    /// `Club.id`. One row per club in the bag.
    @Attribute(.unique) var clubID: String
    /// How far the player hits the club, in yards. Nil for the putter only.
    var distance: Int?
}
```

- Added to `Storage.models`.
- Later fields go here: `shortest`, `longest`, `average`, `weightedAverage`, `strokeCount`. Each is a new optional or defaulted property, which SwiftData migrates by itself.
- A row whose `clubID` is not a club is ignored when the bag is read.

## Store

`Shared/Services/GolfBagStore.swift`, new. `@MainActor @Observable final class GolfBagStore`, built like `LogStore` from a `ModelContext`.

| Member | Does |
|---|---|
| `init(context:)` | Seeds the bag (below), then reads it |
| `bag: GolfBag` | `private(set)`. Read from the rows after every change, so views redraw |
| `toggle(_ club:)` | In the bag: deletes the row. Out of the bag with room: inserts a row with the club's default distance. A full bag stays as it is. A club taken out and put back starts over at its default |
| `setDistance(_ yards: Int, for club: Club)` | Changes the row's distance. Nothing happens for a club not in the bag, or for the putter |

Seeding: the first time the store runs it inserts `GolfBag.standard`. It knows it has run from `SettingsKey.bagSeeded`, a hidden `Bool` default. The flag, not an empty table, decides, so a player who takes every club out does not get the standard 14 back at the next launch. With the flag unset but rows already in the store (a UI test that relaunches keeping the store), the rows are kept and only the flag is set. UI tests clear the store and the settings together at launch, so they start with the standard bag as now.

## Phone

| File | Change |
|---|---|
| `SpotGolf/PhoneServices.swift` | `let golfBag: GolfBagStore`, built from `container.mainContext` |
| `SpotGolf/Models/SettingsKey.swift` | `bag` removed. `bagSeeded` added, default `false`, reset with the others |
| `SpotGolf/Views/GolfBagView.swift` | Reads `services.golfBag.bag` and calls `services.golfBag.toggle(_:)` instead of `@AppStorage`. Buttons and identifiers do not change |
| `SpotGolf/Views/SettingsView.swift` | The "Golf Bag" count comes from `services.golfBag.bag` |

No new text, so the string catalogs do not change.

## Tests

`SpotGolfTests/GolfBagTests.swift` keeps the `Club` tests (unique IDs, `named(_:)`) and adds that every club but the putter has a default distance.

`SpotGolfTests/GolfBagStoreTests.swift`, new, on `Storage.inMemoryContainer()` with settings reset in `setUp`:

- A new store holds the standard 14, each at its default distance, and the putter at none.
- Toggling takes a club out and puts one in, in bag order; the added club has its default distance.
- A full bag takes no more clubs.
- `setDistance` changes the distance, and a second store on the same container reads it back.
- `setDistance` does nothing for a club not in the bag, or for the putter.
- A bag emptied by the player is still empty for a second store on the same container.
- A row with an unknown `clubID` is not in the bag.
- With the seeded flag unset, rows already in the store are kept rather than replaced by the standard bag.

`SpotGolfUITests/GolfBagUITests.swift` does not change.

## Versioning

`feat`, so MINOR. Not breaking: no release saved the settings bag.
