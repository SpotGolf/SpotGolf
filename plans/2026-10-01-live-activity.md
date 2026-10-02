# Live Activity for the current hole

Shows the current hole on the phone's Lock Screen and Dynamic Island during a round.

## Content

| Field | Source |
|---|---|
| Course name | `Round.shortenCourseName` (fixed for the activity) |
| Hole number, par | `round.currentHoleNumber`, `round.currentCourseHole?.par` |
| Yards to green center | `HoleOverview.yardsToGreenCenter` from the phone's location |
| Strokes on the hole, total strokes, score to par | `round`, `HoleOverview.toPar` |

## Parts

| Part | Where | Job |
|---|---|---|
| `HoleActivityAttributes` | `LiveActivity/` (app and extension) | The activity's data |
| `SpotGolfLiveActivity` | new widget extension target | Lock Screen and Dynamic Island views |
| `HoleOverview` | `Shared/Utilities/` | Yards and score to par, used by the map header and the activity |
| `RoundTracker` | `SpotGolf/Services/` | Runs during an active round, even with the app in the background |

## RoundTracker

```
round becomes active ──▶ location updates on (background allowed) ──▶ start activity
each fix ──▶ HoleAdvancer (unless paused by the map) ──▶ RoundStore.startHole
round or fix changes ──▶ new content ──▶ activity.update (only when it differs)
round no longer active ──▶ location updates off ──▶ end activity
```

- Hole auto-advance moves from `RoundMapView` into `RoundTracker`, so holes advance with the phone locked.
  The map pauses and resumes it while the user looks at another hole.
- `LocationManager` keeps a set of owners, so the map or course list closing does not stop the round's updates.
- The phone gets `UIBackgroundModes: location`; background updates are only turned on while a round is active.
- An activity can only be started with the app in the foreground. A failed start is tried again when the app becomes active.

## Risks

- Phone battery use goes up during a round.
- Signing must create a profile for `golf.spot.SpotGolf.LiveActivity`.
