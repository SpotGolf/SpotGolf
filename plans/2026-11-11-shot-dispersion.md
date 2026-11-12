# Caddie: Shot Dispersion

The Caddie's shot pattern on the phone map changes from two trapezoids to a shape that comes out of a shot model (Broadie and Ko, 2009). The same model picks the club and aim. The map also shows the chance of each outcome, such as fairway or water.

This replaces sections 1 (what it draws) and 2 (shot pattern) of plans/2026-11-02-caddie-club-and-aim.md. The rest of that plan stays: the dot menu item, when the Caddie shows, dragging the aim, Reset Caddie, the lie grid, strokes to hole out, and when the advice is worked out.

Phone only. Nothing changes on the watch.

## 1. Decisions

| Topic | Decision |
|---|---|
| Player skill | The average score from ended rounds, as today. No handicap field |
| Short and long | From published numbers for the player's skill. The Caddie tab's low and high yards are not used by the pattern |
| Club and aim pick | Scores the new model's spots. The old pattern code is removed |
| Shapes from the player's own shots (the prompt's Phase 2) | Not on this branch |
| Broadie's fit of angle from driver distance | Not used: skill comes from scores |
| Sample dots and a median ring on the map | Not drawn. The aim marker stays |

## 2. The model

Each shot has two parts that do not depend on each other.

| Part | How it varies |
|---|---|
| Direction | A bell curve around the aim line. Left and right are equally likely |
| Distance | Mostly good shots near full distance, and about 1 in 7 mishits that come up well short. Never shorter than 20% of full distance |

The result is a teardrop: a dense core near full distance, a tail back toward the player, and a little wider at the far end.

| Value | Meaning | From |
|---|---|---|
| Angle spread | How far shots turn off the aim line, in degrees | Skill and club type (section 3) |
| Distance spread | How much distance varies, as a share of full distance | Skill, club type and the start's lie (section 3) |
| Full distance | The club's Caddie average | `ClubDistance.average` |

The exact maths is the prompt's section 1, kept in code comments in `DispersionModel`.

## 3. Numbers

### Skill

One number stands for the player's skill: the driver angle spread, from the average score. `MissAngle` works it out today and keeps doing so.

| Average score | Driver angle spread | Driver distance spread |
|---|---|---|
| 79 or less | 5.4° | 0.09 |
| 87.5 | 6.4° | 0.10 |
| 102 or more | 8.1° | 0.13 |
| No ended rounds | 6.4° | 0.10 |

Between rows, values follow a straight line.

### Club type

| Club | Angle and distance spread |
|---|---|
| Driver | The table above |
| Every other club | Smaller values, solved once so the model matches Broadie's (2008, Table 2) median miss from 125 yards on the fairway: 8.7%, 12.0% and 17.3% of the shot's length for the three skill rows |
| A club that averages under 60 yards | Solved the same way at 50 yards, with distance error 3.2 times direction error, as Broadie reports for short shots |

The solved values are stored as constants. A test solves them again and fails if they drift.

### Start's lie

| Lie | Distance spread times |
|---|---|
| Tee, fairway, green | 1.0 |
| Rough | 1.25 |
| Sand | 1.6 |

### Published or assumed

Every number lives in `DispersionConstants.swift` with one of these labels.

| Number | Label |
|---|---|
| Driver angle spread by score group | Published (Broadie 2008, Table 1; Broadie and Ko 2009, Table 2) |
| Median miss targets from 125 yards | Published (Broadie 2008, Table 2) |
| Short-shot ratio 3.2 | Published (Broadie 2008) |
| Share of good shots (85%) and the good and bad shot curves | Assumption |
| Driver distance spread | Assumption |
| Lie multipliers | Assumption |
| Distance to direction ratio of 1.5 for full shots | Assumption |
| Short shots solved at 50 yards against the 125-yard targets | Assumption |

## 4. Engine

Pure Swift, in `SpotGolf/Utilities/Dispersion`. Shot-local yards: the ball at the origin, +y along the aim line, +x right.

| Piece | Does |
|---|---|
| `DispersionConstants` | Every number in section 3 |
| `DispersionParams` | Angle spread, distance spread, full distance. Made by `forDriver`, `forApproach`, `forShort`, or `for(club:distance:skill:lie:)`, which picks among them |
| `SeededRandom` | SplitMix64 with a seed, and Box–Muller bell-curve values. The same seed gives the same shots |
| `DispersionModel.sample` | `n` shots from a seed |
| `DispersionModel.spots` | 121 spots of equal chance, 11 distances by 11 angles, for the club pick. No random numbers |
| `DispersionContours` | The 50%, 80% and 95% regions: 150,000 shots, each counted with its mirror image, on a grid of 1-yard squares at a full distance of 200 yards; a blur of 3 squares; the density level that holds each share; the outline at that level, simplified to 0.5 yards and its corners cut once |
| `DispersionOutcomes` | The share of 2,000 fixed-seed shots that stop on each lie, from the hole's `LieGrid` |

A pattern grows evenly with its full distance, so a shape is kept by angle spread (to 0.1°) and distance spread (to 0.005) alone, and scaled to each club's distance. Scaling, moving or turning a kept shape is cheap.

## 5. How it runs

```
Caddie turned on, player moved 3 yd, hole / pin / strokes / skill changed
        │
        ▼
ClubAdviser (off the main thread)
  1. lie of the start, from the hole's LieGrid
  2. pick the club and aim: 121 model spots per choice, scored as today
  3. the shape for every club the player can hit, kept for later
  4. outcome chances for the pick
        │
        ▼
Map draws the pick's three regions, turned to the aim and moved to the player

Player drags the pattern
        │
        ├─ each frame: nearest club, its kept contours turned and moved. No new shots
        └─ 150 ms after the finger stops moving: outcome chances worked out again
```

| Limit | Value |
|---|---|
| Spot lookups per pick | The same as today: up to 13 clubs × 35 aims × 121 spots |
| Drag | No sampling on the main thread |

## 6. Map

### What it draws

| Piece | Look |
|---|---|
| 95% region | White fill at 30%, solid 1 pt gray outline |
| 80% region | Dark green fill at 20%, solid 1.5 pt navy outline |
| 50% region | Dark green fill at 45%, solid 2 pt navy outline |
| Hazards in the pattern | The part of each bunker and water shape inside the 95% region: orange-red diagonal stripes with a solid 2 pt orange-red outline. Drawn over the regions |
| Cone lines from the player | Removed |
| Aim line | Thicker: a solid 3 pt yellow line with gray dashes along its middle, from the player's dot to the aim point's ring |
| Aim point | As today: a yellow ring, with the club and yards in a yellow capsule beside it |
| Line to the pin | As today |

The look follows the mock-up from 2026-11-11, which had two regions; the model gives three. Drawn over the map as today, so touches pass through.

### Dragging

As today, with one change: a drag starts inside the 95% region, between the player and that region, or on the aim point's marker.

### Outcome chip

A capsule above the suggestion legend, below Reset Caddie, shown while the pattern shows.

| Topic | Decision |
|---|---|
| Text | For example "52% fairway · 6% hazard". Says "green" in place of "fairway" when the aim point is on the green |
| Hazard | Sand plus water. The course data has no out of bounds |
| Tap | Opens the stats sheet |
| VoiceOver | "Caddie: 7 Iron, 52% fairway or green, 6% hazard" |
| Identifier | `CaddieOutcome` |
| Contrast | White text on a dark capsule, above 4.5:1 |

### Stats sheet

A full-height sheet, so every row shows without scrolling.

| Row | Example |
|---|---|
| Club | 7 Iron, 148 yards |
| Fairway or green | 52% |
| Rough | 42% |
| Sand | 4% |
| Water | 2% |
| Left to right, 95% of shots | ±24 yards |
| Short to long, 95% of shots | 98–161 yards |
| Skill | A picker: My scores, Low scores, Mid scores, High scores |

| Topic | Decision |
|---|---|
| My scores | The default. Uses the average score, or the Mid row with no ended rounds |
| Low / Mid / High | The three rows of section 3's skill table |
| Saved | In `UserDefaults`, key `caddieSkill` |
| Identifiers | `CaddieStatsClub`, `CaddieStatsFairway`, `CaddieStatsRough`, `CaddieStatsSand`, `CaddieStatsWater`, `CaddieStatsLateral`, `CaddieStatsDownrange` for the rows, `CaddieSkill` for the picker, `CloseCaddieStats` for Done |

## 7. Code changes

| File | Change |
|---|---|
| `SpotGolf/Utilities/Dispersion/*.swift` | New: the engine pieces in section 4 |
| `SpotGolf/Utilities/ShotPattern.swift` | Removed. `BellCurve` moves to the engine |
| `SpotGolf/Utilities/MissAngle.swift` | Its numbers move to `DispersionConstants`. Gains the skill picker's choice |
| `SpotGolf/Utilities/ClubAdvice.swift` | `ClubAdvice`, `CaddieShot` and `ClubAdviser` use `DispersionParams`, model spots, contours and outcomes. `corners(k:)` goes |
| `SpotGolf/Services/CaddieStore.swift` | Holds the skill choice and the skill it gives |
| `SpotGolf/Views/RoundMap/RoundMapLayer.swift` | Draws the three regions, the striped hazards inside them and the thicker aim line. Trapezoids and cone lines go. New drag start area |
| `SpotGolf/Views/RoundMap/RoundMapView.swift` | Outcome chances with the 150 ms wait, and the stats sheet |
| `SpotGolf/Views/RoundMap/MapButtonBar.swift` | The outcome chip |
| `SpotGolf/Views/RoundMap/CaddieStatsSheet.swift` | New: the stats sheet |
| `SpotGolf/Views/RoundMap/CaddieDragGesture.swift`, `RoundMapState.swift` | "Cones" renamed to "pattern" |
| `plans/2026-11-02-caddie-club-and-aim.md` | A note at the top that sections 1 and 2 are replaced by this plan |

## 8. Tests

| Test | Checks |
|---|---|
| `DispersionModelTests` | The prompt's reference table (Mid and High cases); the same seed gives the same shots; left and right balance within 0.5 yards; the tail is short, and the median is past the mean; 121 spots of equal chance |
| `DispersionContoursTests` | The 95% region holds 95% ± 1.5% of fresh shots; 50% is inside 80% is inside 95%; the same key returns the kept shape |
| `DispersionCalibrationTests` | Solves the non-driver values again and compares them with the stored constants. Logs the rough-lie median miss against Broadie's, and the fairway rates on a 35-yard fairway against Broadie and Ko's 54% and 44%, without failing |
| `DispersionOutcomesTests` | On a made-up hole: the shares add to 100%; water beside the fairway raises the water share |
| `ShotPatternTests` | Removed |
| `ClubAdviceTests`, `ClubAdviceRealCourseTests` | Updated to the new pattern. Each real-course case checked on the map again |
| `MissAngleTests` | The picker's choices give the three rows |
| `InRoundUITests+Caddie` | As today, plus: the outcome chip shows with the pattern, opens the stats sheet, and changing the skill changes the numbers |

## 9. Limits

| Limit | Effect |
|---|---|
| Every club but the driver uses the 125-yard values | A fairway wood's pattern is narrower than a driver's by a step, not a slope |
| Full distance is the Caddie average | The model's good shots go a little past it and its mishits well short, so the densest part of the pattern sits just past the aim point, and the average shot just short of it |
| No out of bounds or trees in the course data | They count as rough |
| The pattern is centered | A player who misses one way gets a centered shape |
