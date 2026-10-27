# Green View

MapKit stops zooming before putts can be told apart: a 6 ft putt is a few points on screen. Green View is a second view of the shown hole's green that the app draws itself, so it can zoom in as far as needed. It replaces the map while it is open; the hole header stays.

## 1. Getting in and out

```
          Map ──[⛳ button]──────────────► Green View
           │                                    │
           └────[X in the top bar]──────────────┤
           └────[hole changes]──────────────────┘
```

| Way | When |
|---|---|
| **⛳ button** (`flag`) above the Edit button, bottom left | Shown when the shown hole has a green outline. Past rounds too. |
| **X** in the top bar | Always. Also turns off edit mode. |
| **Hole changes** | Closes. A hole picked in the header, or the scorecard's edit button. |

**Green View is always in edit mode**, since it is for marking putts. Opening it turns on edit mode, and it has no Edit or Done button: only its X closes it and ends editing. The map holds the edited hole on screen while editing (`editingHoleIndex`), so the display hole moving on does not close Green View either; after X, the map moves on to the display hole.

The top bar sits under the hole header, the same material as the map buttons: **"Green View"** on the left, **X** on the right (`accessibilityIdentifier("CloseGreenView")`). It makes it plain which view is showing and how to leave.

Opening and closing cross-fade (0.2 s). The map keeps its camera, so closing returns to where the map was.

## 2. What it draws

All drawn with SwiftUI `Canvas` and views, no MapKit. Back to front:

| Layer | Look |
|---|---|
| Background | Fringe green, darker than the green |
| Bunkers and water within the view | Sand and blue fills, from the course features |
| Green | Lighter green fill, thin white outline |
| GPS track on the hole | Blue dashed line, as on the map |
| Lines between strokes | White, with feet on each (see 4) |
| Spots | The same `SpotPin` as the map, numbered by stroke |
| Pin | The same `PinFlag` |
| Player | Blue dot with a white ring, active round only |

The map style setting does not apply: Green View always looks the same.

## 3. Camera

- **Turned** so the hole's direction of play points up (`MapGeometry.heading`), as on the map.
- **Opens** fitted to the green plus 5 yd on every side.
- **Pinch** zooms, **drag** pans. Zoom out stops at the green plus 15 yd. Zoom in stops at 4 points per inch (a 1 ft gap is about 50 points).
- **Double tap** zooms in 2x at the tap. Pinching out is the only way to zoom out.
- A single tap on the ground does nothing: unlike the map, Green View has no tap target.
- Spots and the pin keep their on-screen size at any zoom.
- Strokes outside the drawn area are not drawn; lines to them run off the edge.

Converting between ground and screen is a small local projection (meters east and north from the green center, turned and scaled). It goes in a new `GreenProjection` in `SpotGolf/Utilities`, with its own unit tests, and plays the part `MapProxy` plays on the map.

## 4. Distances

In feet, rounded to whole feet.

| Distance | Where |
|---|---|
| Between strokes on the hole | On the middle of each line, always shown (tapping a spot opens it, as in edit mode on the map). |
| Player to pin | In the top bar, after "Green View": "Green View · 18 ft". Active round only. |

## 5. Editing

Green View uses the map's editing gestures, so the player learns one set:

| Gesture | Does |
|---|---|
| Long press on the ground | Adds a spot (club guessed, `hitAt` from the track) |
| Tap a spot | Opens `SpotEditSheet` |
| Long press and drag a spot | Moves it, lifted above the finger, with a bullseye where it lands |
| Long press and drag the pin | Moves the pin, lifted above the finger, with a bullseye where it lands |
| Suggestion pins | Shown, tap to add |

**Moving the pin** uses `RoundStore.setPin`, so it is saved as the player's pin (source `.set`) and reaches the watch as the Set pin button's does. It must land on the green: a drop off the green springs back, with a warning haptic. Past rounds can move the pin too.

The bottom shows the suggestion legend, as in edit mode on the map, in place of the Set pin button.

## 6. Code

| Piece | Change |
|---|---|
| `RoundMapView` | `@State greenView: GreenViewState` (open and close rules, unit tested). Shows `GreenView` over `RoundMapLayer`, so the map keeps its camera. |
| `MapButtonBar` | ⛳ button (`flag`) and Edit in one capsule at the bottom left, styled as the map capsule, and hidden while Green View shows. The map capsule (map style, follow location) is hidden while Green View shows: none of it applies there. `MapInfoOverlay` is hidden too; the top bar has the feet to the pin. |
| `GreenView` (new, `Views/RoundMap`) | Top bar, `Canvas` for the ground, overlays for spots, pin, labels, target. Gestures from section 5. |
| `GreenProjection` (new, `Utilities`) | Ground to screen and back, fit, zoom and pan limits. |
| `SpotActions` (new, `Views/RoundMap`) | Adding a spot and taking a suggestion, used by `RoundMapLayer` and `GreenView`. The spot drag stays in each view, since it converts points differently. |
| `StrokeLine`, `DistanceLabel` | `StrokeLine.feet`; `DistanceLabel` takes a unit (yards or feet) and an identifier. |
| `Round.metersOffGreen` | Meters from a point to the green's edge, 0 on it, for the auto close. |

## 7. Compatibility

Phone only. No saved data or watch messages change. `feat`, MINOR.

## Checks

- Unit: `GreenProjection` round trip (ground to screen to ground within 1 cm), fit to green, zoom limits, turned by heading.
- Unit: open and close rules (button opens, X closes, hole change closes; walking onto the green does not open it).
- UI test: ⛳ opens Green View in edit mode with no Edit button, X closes it and ends edit mode, the map keeps its camera.
- UI test: in edit mode, long press adds a spot in Green View, and it shows on the map after closing.
- By hand on a real round (simulator clone with a round replayed by `replay-round.py`): walk onto a green, Green View stays closed; putts read in feet; dragging the pin off the green springs back.
