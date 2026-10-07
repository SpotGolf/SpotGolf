# Pin location

## Goal

The player marks where the pin is on each hole from the watch or the phone. The phone's map shows it as a small flag.

## Watch

- Under the hole title and arrows, a "Set pin location" button shows while the latest GPS fix is inside the shown hole's green polygon (from the course data).
- Tapping it saves that fix as the shown hole's pin. Tapping again replaces it.
- Off the green, or on a hole with no green polygon, the button is hidden.

## Phone

- The same "Set pin location" button shows in the middle of the map's bottom bar, between the edit and location buttons.
- It shows only during a round, while not editing, and while the phone's latest GPS fix is inside the shown hole's green.

## Model

| | |
|---|---|
| Type | `PinLocation`: hole index, latitude, longitude, `setAt` |
| Stored as | `Round.pins: [PinLocation]`, at most one per hole |
| Set by | `Round.setPin(_:onHole:at:)`. Refused unless the point is inside that hole's green |
| Merged | Per hole, the later `setAt` wins |
| Saved rounds | `pins` is read with `decodeIfPresent`, so rounds saved by older builds still load |

## Sync

Pins sync both ways, like the display hole:

- `SyncMessage.pins(PinsMessage)` on every change made on a device.
- `SyncContext.pins`, so a change still arrives while the other device is unreachable.
- `StartRound.pins`, so a resumed round keeps its pins on the watch.

`RoundStore.onPinsChanged` reports changes made on this device; merged changes from the other device are not reported.

## Phone map

The shown hole's pin is drawn at its coordinate: a thin dark pole with a small triangular flag at the top. The base of the pole sits on the pin. The flag's color depends on where the pin came from; see `2026-10-06-shared-pins.md`.

## Distances

Distances to the middle of the green go to the hole's pin (`Round.targetCoordinate`), or to the green's center when the hole has no pin. A `center` pin is the green's center, so it gives the same number.

| Where | Measured to | Label with a center pin | Label with a shared or set pin |
|---|---|---|---|
| Watch middle number | Pin | Mid | Pin |
| Phone header | Pin | Par 4 - N yds | Par 4 - N yds |
| Phone distance box | Pin | yds to center | yds to pin |
| Phone tapped point | Pin | To green | To pin |
| Live Activity | Pin | yds to center | yds to pin |

Front and back stay on the green's edges along the line of play. The line of play, the hazards ahead and the elevation still use the green's center, since they describe the green, not the pin. `Feature.center` in the course data is not changed.

## Not in this change

- Placing the pin by hand on the map.
