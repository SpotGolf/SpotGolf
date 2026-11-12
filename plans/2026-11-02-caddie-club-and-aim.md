# Caddie: Club and Aim

> Sections 1 (what it draws) and 2 (shot pattern) are replaced by plans/2026-11-11-shot-dispersion.md.

The second part of the caddie. From the player's location during a round, it picks the club and the aim point with the lowest expected score for the hole, and draws the club's shot pattern on the map. The pattern comes from the club's distance range in the Caddie (plans/2026-11-02-caddie-club-distances.md) and a miss angle from published data for golfers of the player's average score. The player never says where they aimed.

Phone map only. Nothing changes on the watch.

## 1. Map overlay

### Dot menu

A third item in the map's dot menu, after Green View and Distances, that works the way Distances does.

| Topic | Decision |
|---|---|
| Item | Toggle "Caddie", with the `DriverHead` icon from the Caddie tab |
| Starts | Off each time the map opens, as Distances does. Not saved |
| Shown | Only while the round is active: the advice comes from the player's location |
| Accessibility identifier | `CaddieAdvice`, apart from the Caddie tab's button |

### What it draws

```
              ┌───────────────────────┐   outer: 2σ, purple
              │  ┌─────────────────┐  │   inner: 1σ, blue
              │  │       ◎ 7i 148  │  │   aim point, with the club and yards to it
              │  └─────────────────┘  │
              └───────────────────────┘
                         ┊                thin dashed line from the player to the aim point
                         ┊
                         ●  player
```

| Piece | Look |
|---|---|
| Outer shape | The recommended club's 2σ trapezoid (section 2): a dotted purple 2 pt outline, filled purple at 15% |
| Inner shape | Its 1σ trapezoid: a dotted blue 2 pt outline, filled blue at 35% |
| Cone lines | Dotted 2 pt lines from the player to each shape's near corners, purple for the outer and blue for the inner, so each whole cone shows |
| Aim line | A yellow 1 pt dashed line from the player to the aim point |
| Aim point | A small yellow ring at the aim point. Next to it, a label with the club's short name and the yards from the player to the aim point, for example "7i 148" |
| Line to the pin | A dotted yellow 2 pt line from the aim point's ring on to the pin, or the green's center without one, with its yards on its middle in a yellow box, as Distances has them in white. None when the aim point is on the green. Identifier `CaddieToPin` |
| VoiceOver | The aim point reads "Caddie: 7 Iron, 148 yards", and the line's box its yards. Identifier `CaddieAim` |

The aim point is where the club's average distance lands along the aim line.

### When it shows

| Case | Shows |
|---|---|
| Toggle on, round active, a location, the shown hole is the round's display hole | Yes |
| The player is on the green, or within the Green Zone setting of its edge | No: putts and chips. The Caddie's distances leave those shots out too |
| The hole has no green in the course data | No: there is nothing to score against |
| No club but the putter in the bag | No |
| A past round, or another hole shown | No |

The trapezoids, aim line and aim point are drawn over the map like the hazard bubbles, and let touches through. Map shapes (`MapPolygon`, `MapPolyline`) were tried first: the map drew them only when something else made it redraw, such as a touch, a camera move or a new location, so advice worked out in the background stayed hidden while the player stood still. A map annotation for the aim point would block a long press that adds a spot under it. The fills are see-through, so the spots and flag under them still show.

### Moving the aim

The player can press and drag the cones to aim somewhere else.

| Topic | Decision |
|---|---|
| Where a drag starts | Inside the outer cone, from the player to the far edge of the outer trapezoid, or on the aim point's marker |
| What it changes | Aim and distance. The point under the finger keeps its place, and the shot is redrawn straight at it with the club whose Caddie average is nearest the yards to it, a tie going to the longer club. The putter is never picked, and the driver only for a tee shot |
| The map | Holds still while the cones are dragged. A drag that starts off the cones pans the map as before. A tap or a long press on the cones still drops a target or adds a spot |
| How long the aim stays | It is a point on the ground. As the player walks, the shot is redrawn from them to it, and its club can change. It stays until the shown hole changes, a stroke is added to or removed from the hole, the Caddie is turned off, or the player taps Reset Caddie |
| Reset Caddie | A capsule button above the suggestion legend, like Set pin location, shown only while the cones are where the player dragged them. It puts them back on the Caddie's pick. Not in Green View. Identifier `ResetCaddie` |
| Its score | None: the player's own aim is not scored |

How the drag works: a one-finger pan recognizer on the map that begins only when the touch starts on the cones. The map's own pan waits for it to fail, so a drag off the cones pans the map with no delay to speak of, and a drag on them never does.

## 2. Shot pattern

### Distance

From the club's `ClubDistance` in the Caddie:

| Value | From |
|---|---|
| Average a | `average` |
| Short spread s | `average − low` |
| Long spread l | `high − average` |

### Miss angle

The miss angle is the angle between the line from the ball to where it stopped and the line to the target. Its standard deviation σ comes from published data. The player is matched by their average score in SpotGolf.

| Source | Golfers | σ |
|---|---|---|
| Broadie (2008), Table 1 | Scores 70–83 | 5.4° |
| | Scores 84–97 | 6.4° |
| | Scores 98–120 | 8.1° |
| Broadie and Ko (2009), Table 2 | Average 80 | 5.5° |
| | Average 100 | 7.9° |

| Topic | Decision |
|---|---|
| Formula | σ = 5.5° + 0.12° × (score − 80), kept between 5.4° and 8.1°. It runs through Broadie and Ko's 80 and 100 golfers, and gives Broadie's 6.4° at 87.5, inside the 84–97 group |
| Average score | The average strokes per hole, penalty strokes included, over every hole with strokes in an ended round, times 18. That covers 9-hole and partly played rounds |
| No ended rounds | 6.4°, the 84–97 group |
| Clubs | The same angle for every club. Published angles are for driver tee shots only; one amateur's 6,436 shots work out to about 4.5° at 150 yards, so this errs wide for irons, which is the safe side |
| Center | Zero. Both papers found misses centered on the target, with angle and distance separate |

### Shape

With the shot going from the start toward an aim direction, and k the number of standard deviations:

| Edge | Where |
|---|---|
| Near edge | a − k·s from the start, square to the aim line |
| Far edge | a + k·l from the start, square to the aim line |
| Sides | k·σ either side of the aim line, from the start |
| Near width | 2 · (a − k·s) · tan(k·σ) |
| Far width | 2 · (a + k·l) · tan(k·σ) |

That is an isosceles trapezoid. Strictly, the ends are arcs; at these angles the far end bulges by less than 1% of its distance, so the shape keeps 4 corners.

| k | Share of shots inside | Drawn as |
|---|---|---|
| 1 | About 46% (68% on distance times 68% on angle) | Inner shape. Its depth matches the Caddie's bar |
| 2 | About 91% (95% times 95%) | Outer shape |

Examples at 6.4°, from the Caddie's starting ranges:

| Club | k | Depth | Near width | Far width |
|---|---|---|---|---|
| 7 iron, 145 yd | 1 | 128–157 yd | 29 yd | 35 yd |
| | 2 | 111–169 yd | 50 yd | 77 yd |
| Driver, 230 yd | 1 | 202–248 yd | 45 yd | 56 yd |
| | 2 | 174–266 yd | 79 yd | 121 yd |

### Samples

To score a pattern, it is split into 121 landing spots of equal chance: 11 distances times 11 angles.

| Axis | The 11 values |
|---|---|
| Distance | The split bell curve with its peak at a, spread s below and l above, at chances p = (i − 0.5) / 11 for i = 1 … 11. Below a, at p < s/(s + l): a + s · Φ⁻¹(p · (s + l) / (2s)). Above a: a + l · Φ⁻¹(0.5 + (p − s/(s + l)) · (s + l) / (2l)) |
| Angle | σ · Φ⁻¹(p) at the same chances |

Φ⁻¹ is the inverse of the standard bell curve, worked out with Acklam's approximation. Each spot is the start moved by its distance along the aim direction turned by its angle.

## 3. Picking the club and aim

### Choices

| Topic | Decision |
|---|---|
| Clubs | Each club in the bag with a Caddie distance, the putter left out. The driver only for a tee shot: while the display hole has no strokes yet, as club guesses do |
| Aims | From 45° left to 45° right of the line from the player to the pin, which covers doglegs. Each club is tried every 3°, then at each whole degree within 2° of its best. The pattern is about 13° wide, so its score changes little over 3° |
| Pin | `Round.targetCoordinate`: the hole's pin, or the green's center without one |
| Count | Up to 13 clubs × 35 aims × 121 spots, about 55,000 spot lookups |

### Lie of each spot

| Lie | Where | Wins over |
|---|---|---|
| Water | Inside any water on the course | Everything |
| Sand | Inside any bunker on the course | Green, fairway, rough |
| Green | Inside this hole's green | Fairway, rough |
| Fairway | Inside this hole's fairway or tee boxes | Rough |
| Rough | Anywhere else, other holes' fairways and greens included | |

Water and bunkers come from the whole course, since a ball can reach another hole's water. The lies are looked up on a 2-yard grid. Each square's lie is worked out the first time a spot lands in it, against the features whose bounding box holds it, and kept until the display hole changes.

### Strokes to hole out

From a spot, the average strokes to hole out, from Broadie's PGA Tour table in *Every Shot Counts* (ShotLink data, 2004 to 2012). Off the green, by yards to the pin:

| Yards | Fairway | Rough | Sand |
|---|---|---|---|
| 20 | 2.40 | 2.59 | 2.53 |
| 40 | 2.60 | 2.78 | 2.82 |
| 60 | 2.70 | 2.91 | 3.15 |
| 80 | 2.75 | 2.96 | 3.24 |
| 100 | 2.80 | 3.02 | 3.23 |
| 120 | 2.85 | 3.08 | 3.21 |
| 140 | 2.91 | 3.15 | 3.22 |
| 160 | 2.98 | 3.23 | 3.28 |
| 180 | 3.08 | 3.31 | 3.40 |
| 200 | 3.19 | 3.42 | 3.55 |
| 220 | 3.32 | 3.53 | 3.70 |
| 240 | 3.45 | 3.64 | 3.84 |
| 260 | 3.58 | 3.74 | 3.93 |
| 280 | 3.69 | 3.83 | 4.00 |
| 300 | 3.78 | 3.90 | 4.04 |
| 320 | 3.84 | 3.95 | 4.12 |
| 340 | 3.88 | 4.02 | 4.26 |
| 360 | 3.95 | 4.11 | 4.41 |
| 380 | 4.03 | 4.21 | 4.55 |
| 400 | 4.11 | 4.30 | 4.69 |
| 420 | 4.15 | 4.34 | 4.73 |
| 440 | 4.20 | 4.39 | 4.78 |
| 460 | 4.29 | 4.48 | 4.87 |
| 480 | 4.40 | 4.59 | 4.98 |
| 500 | 4.53 | 4.72 | 5.11 |
| 520 | 4.66 | 4.85 | 5.24 |
| 540 | 4.78 | 4.97 | 5.36 |
| 560 | 4.86 | 5.05 | 5.44 |
| 580 | 4.91 | 5.10 | 5.49 |
| 600 | 4.94 | 5.13 | 5.52 |

On the green, by feet to the pin:

| Feet | Putts | Feet | Putts |
|---|---|---|---|
| 1 | 1.00 | 15 | 1.78 |
| 2 | 1.01 | 20 | 1.87 |
| 3 | 1.05 | 25 | 1.94 |
| 4 | 1.13 | 30 | 2.00 |
| 5 | 1.23 | 40 | 2.12 |
| 6 | 1.34 | 50 | 2.21 |
| 7 | 1.42 | 60 | 2.28 |
| 8 | 1.50 | 90 | 2.40 |
| 10 | 1.61 | 100 | 2.45 |

| Topic | Decision |
|---|---|
| Between rows | Straight-line between the two nearest rows |
| Past the ends | The nearest end row: under 20 yards uses the 20-yard row, past 600 the 600-yard row, under 1 foot 1.00, past 100 feet 2.45 |
| Water | 1 penalty stroke plus the rough value from the drop spot: where the line from the start to the spot last goes into the water, as the rules use, found by stepping back along it from the spot on the lie grid until it leaves the water |
| Why a tour table for amateurs | It is the only full published table. The engine uses only the differences between spots (fairway against rough, short against long), and those keep their order for amateurs. Broadie (2011) found the rough costs pros more than amateurs, so this leans a little toward the fairway |

### Choice

| Topic | Decision |
|---|---|
| Expected score of a choice | 1 + the average of its 121 spots' strokes to hole out |
| Pick | The club and aim with the lowest expected score |
| Ties | Within 0.005 strokes, the aim nearer the line to the pin |

## 4. When it is worked out

| Worked out again | Not worked out |
|---|---|
| The toggle is turned on | On every redraw |
| The player moves 3 yards or more from where it was last worked out | GPS fixes that move the player less than 3 yards |
| The display hole changes, or its pin moves | |
| A stroke is added to or removed from the display hole: the driver comes and goes | |
| The Caddie's distances or the miss angle change | |

The lie grid is kept between runs on the same hole, so a run costs only the spot lookups. On the Broadlands tees, in a debug build on the simulator, a hole's first run takes 70 to 265 ms and later runs 9 to 164 ms. That is over 20 ms, so it runs off the main thread on the `ClubAdviser` actor. A newer run cancels an older one, and an older run's answer is dropped. The advice on the map stays until the new one is in.

## 5. Limits

| Limit | Effect |
|---|---|
| The course data has no out of bounds or trees | Those count as rough, so the engine never steers away from them |
| Caddie distances are where the ball stopped (carry plus roll) | For water in front, the near edge overstates how far the ball flies, so a carry over water looks a little safer than it is |
| The start's lie doesn't change the pattern | Shots from the rough or sand spread more than the pattern shows |
| The miss angle is a group number | A player who misses one way more often gets a centered pattern |
| The advice comes from the player's location, not the ball's | It is right once the player is at the ball. While walking, it follows them |

## 6. Code

| Piece | Where | Does |
|---|---|---|
| `MissAngle` | `SpotGolf/Utilities` | σ from the ended rounds' average score. Unit tested |
| `StrokesToHoleOut` | `SpotGolf/Utilities` | The table in section 3, by lie and yards or feet. Unit tested |
| `LieGrid` | `SpotGolf/Utilities` | The lie of a point on the 2-yard grid, for one hole, with water drop spots. Unit tested |
| `ShotPattern` | `SpotGolf/Utilities` | One club's pattern from a start along an aim: its 121 spots and its 1σ and 2σ corners. Holds Φ⁻¹. Unit tested |
| `GroundPlane` | `SpotGolf/Utilities` | The course flattened to meters east and north of a point, for the pieces below |
| `ClubAdvice` | `SpotGolf/Utilities` | Picks the club and aim (section 3). Returns the club, the aim point and the pattern. Unit tested |
| `ClubAdviser` | `SpotGolf/Utilities/ClubAdvice.swift` | An actor that works out a request off the main thread, and keeps the lie grid for the hole. Unit tested |
| `ClubAdviceState` | `SpotGolf/Utilities/ClubAdvice.swift` | Makes a request at the times in section 4, and shows only the newest answer. Unit tested |
| `CaddieStore` | `SpotGolf/Services` | Adds the miss angle, worked out with the shots when an ended round changes |
| `RoundMapView` | `SpotGolf/Views/RoundMap` | Holds `showsCaddie`, like `showsStrokeLines`, and a `ClubAdviceState` it updates when the location or what the advice comes from changes |
| `MapButtonBar` | `SpotGolf/Views/RoundMap` | The Caddie toggle in the dot menu, during an active round only |
| `RoundMapLayer` | `SpotGolf/Views/RoundMap` | Draws the two trapezoids, the aim line and the aim point over the map, redrawn as the camera moves (section 1) |
| `CaddieAimMarker` | `SpotGolf/Views/RoundMap/MapMarkers.swift` | The aim point's ring and label |
| `CaddieShot` | `SpotGolf/Utilities/ClubAdvice.swift` | A club's pattern from the player, as the map draws it: the Caddie's pick, or the shot at the player's dragged aim. Unit tested |
| `CaddieAim` | `SpotGolf/Views/RoundMap/RoundMapState.swift` | Where the player dragged the cones to, and the hole and strokes it is for |
| `CaddieDragGesture` | `SpotGolf/Views/RoundMap` | The pan recognizer that moves the cones |

## 7. Tests

| Test | Checks |
|---|---|
| `MissAngleTests` | No rounds gives 6.4°; averages of 80 and 100 give 5.5° and 7.9°; the limits at 5.4° and 8.1°; a 9-hole round counts at 18 holes; penalty strokes count |
| `StrokesToHoleOutTests` | Table values on the rows; straight-line between rows; the ends; putts by feet |
| `LieGridTests` | Each lie, and which wins where shapes overlap; another hole's fairway is rough and its water is water; the water drop spot is where the line goes in |
| `ShotPatternTests` | 121 spots; their distances and angles match the split bell curve and σ; the 1σ and 2σ corners match the widths in section 2's example table |
| `ClubAdviceTests` | On made-up holes: open ground aims at the pin; water left of the green moves the aim right; water short of the green with a club that can't clear it picks a shorter club to lay up; the driver only off the tee; ties go to the aim nearer the pin line; no advice in the cases of section 1; worked out again at the times of section 4; a dragged aim takes the club nearest its yards |
| `ClubAdviceRealCourseTests` | On the Broadlands course (`Data/Simulations`), holes with water or bunkers near the landing area: the advice steers away from them. Each case checked by hand on the map first |
| `InRoundUITests+Caddie` | The dot menu's Caddie item shows `CaddieAim`, and picking it again hides it; the line from the aim on to the pin has its yards; dragging the cones changes the club, does not pan the map and shows Reset Caddie; Reset Caddie, and turning the Caddie off and on, go back to its pick; a drag off the cones pans the map |
| `OutsideRoundUITests+PastRound` | The item is not in a past round's menu |

## 8. Sources

| Source | Used for |
|---|---|
| Broadie (2008), [Assessing Golfer Performance Using Golfmetrics](https://business.columbia.edu/sites/default/files-efs/pubfiles/2851/broadie_wscg_v_200802.pdf), *Science and Golf V* | Miss angle σ by score group, measured against the middle of the fairway; longer hitters are straighter |
| Broadie and Ko (2009), [A simulation model to analyze the impact of distance and direction on golf scores](https://business.columbia.edu/sites/default/files-efs/pubfiles/4703/wsc_golf_broadie_ko.pdf), *Winter Simulation Conference* | σ for 80 and 100 golfers; the angle is a bell curve centered on the target and separate from distance; a fixed angle with a distance range reproduces fairways hit |
| Broadie (2011), [Assessing Golfer Performance on the PGA TOUR](https://columbia.edu/~mnb2/broadie/Assets/strokes_gained_pga_broadie_20110408.pdf) | Rough costs pros more than amateurs |
| Broadie (2014), *Every Shot Counts*, as reproduced by [WhyGolf](https://whygolf.com/pages/strokes-gained-calculator) | Strokes to hole out by lie and distance |
| Pine Golf Lab, [6,436 shots analyzed](https://pinegolflab.com/shot-shape-distribution-analysis/) | One amateur's iron angle, about 4.5° at 150 yards: a check that the driver angle errs wide for irons |
