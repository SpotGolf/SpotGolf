# Caddie: Club Distances

The first part of the caddie: how far the player hits each club. Each club starts from its distance in the bag and a typical spread for amateur golfers, then moves toward the player's own shots from past rounds. Club guesses use the same numbers. It gets its own screen on the home screen. To make room, the buttons at the top of the home screen move to a tab bar at the bottom.

## 1. Tab bar

A bar fixed at the bottom of the home screen. The main area above it scrolls on its own; the bar never moves.

```
┌────────────────────────────────────────┐
│ ⌚                         End Round   │  navigation bar
│ Rounds                                 │
│                                        │
│   main area: the active tab's screen   │
│                                        │
├────────────────────────────────────────┤  line at the top of the bar
│  🕘     🏌     ( + )     ⛳︎     ⚙     │
│ Rounds Caddie New Round  Putt  Settings│  (labels are for VoiceOver only)
└────────────────────────────────────────┘
```

| Place | Tab | Icon | Main area | Accessibility label |
|---|---|---|---|---|
| 1, far left | Rounds | A scorecard, our own icon | The list of rounds, as today | "Rounds" |
| 2 | Caddie | A driver head seen from the face, filled, with the face's lines, our own icon | Club distances (section 3) | "Caddie" |
| 3, middle | New round | `plus.circle.fill`, larger than the rest | The new round questions (section 2) | "New Round", or "Current Round" while a round is in progress |
| 4 | Putt Data Sharing | A blade putter head, our own icon | The Putt Data Sharing screen | "Putt Data Sharing" |
| 5, far right | Settings | `gearshape` | The Settings screen | "Settings" |

| Topic | Decision |
|---|---|
| Look | Flat icon buttons with no labels and no glass. A thin line across the top of the bar and the bar background (`.bar`) show it is a button panel |
| Active tab | Its icon is the accent color and filled (`gearshape.fill`, and a filled version of each of our own icons); the others are secondary |
| Our own icons | SF Symbols has no scorecard, driver or putter. Each is a template image in `Assets.xcassets`. The scorecard and putter come in two versions: outline, and filled for the active tab. The driver is always filled, so its face lines show; only its color changes |
| Starts on | Rounds, every launch |
| Screens pushed from a tab | Cover the bar, like the map does now: Golf Bag and its Distances from Settings, a round's map from Rounds |
| Navigation bar | Each tab's own title: "Rounds", "Caddie", "Select Course" (and its later steps), "Putt Data Sharing", "Settings" |
| Watch status | Top left, on every tab |
| End Round | Top right, on the Rounds tab, while a round is active |
| Settings and Putt Data Sharing | No longer sheets: no Done button, no navigation stack of their own |

## 2. New round

| Case | + does |
|---|---|
| No round in progress, watch paired | Shows the new round questions in the main area: course, nines and starting hole, tee. Same steps and Back buttons as today; no Cancel, since another tab leaves |
| No round in progress, no watch | Disabled, as New Round is now |
| A round in progress (starting, active or ending) | Opens that round's map. Does not change the active tab |

The course search field is our own, not the system one, which sits under the tab buttons and pushes them up.

| Topic | Decision |
|---|---|
| Where | At the top of the tab bar, above the buttons, while the course list shows. The bar grows taller; the buttons stay where they are on every tab |
| Typing | The field rides up on the keyboard. The buttons stay put, under the keyboard, and show again when it goes down |
| Cancel | Shown beside the field while typing: empties it and puts the keyboard away. Search on the keyboard, or scrolling the list, also puts it away |
| Leaving the tab | Empties the search |

Once the round starts, its map takes over the screen as now, and the active tab becomes Rounds, so Back from the map shows the round at the top of the list.

The course picker that Settings opens to import a track stays a sheet with its own Cancel.

## 3. Club distances

### Which shots count

A shot's distance is the yards from its spot to the next spot on the same hole. GPS spots give where the ball stopped, so it is carry plus roll.

| Shot | Counts |
|---|---|
| From an ended round | Yes |
| From a round in progress | No |
| Putter, or no club | No |
| Last stroke of a hole | No: where the ball went is not known |
| With penalty strokes | No: the next spot is a drop or a re-tee |
| Rated thumbs down | No |
| Rated thumbs up, meh, or unrated | Yes |
| Hit from inside the Green Zone (on the green, or within the Green Zone setting of its edge) | No: a chip, not a full shot |
| On a hole whose course data has no green | Yes: the Green Zone can't be checked |

### Starting estimate

Every club but the putter starts with these, before any shots:

| Value | Starts at |
|---|---|
| Average | The club's distance in the bag: the player's own number from Club Distances, or the default |
| Short spread | 12% of the average |
| Long spread | 8% of the average |
| Weight | 5 shots: the starting estimate counts as much as 5 real shots |

The range runs from the average minus the short spread to the average plus the long spread. That is one standard deviation each side, where about two in three shots land. A 7 iron at 145 starts at 128 to 157, a driver at 230 at 202 to 248.

Why these numbers (sources in section 6):

| Finding | What it sets |
|---|---|
| On a launch monitor, skilled golfers' carry varies about 6% or less from shot to shot | The spread can't be smaller than this |
| On the course, amateurs land within 5 yards of their own 7 iron average only 12.5% (25 handicap) to 18.5% (scratch) of the time | On-course spread is much wider than on the range. Ours is wider than 6% |
| A 15 handicap's shots spread 25 to 30 yards from short to long | 20% of a 145 yard 7 iron is 29 yards |
| Distance errors are about the same share of the distance for any shot over 60 yards | Spread as a share of the average, the same for every club |
| Mishits (fat, chunked) make shots come up short far more often than long | Short spread larger than long |

### Adjusting with shots

Each counted shot moves the club's numbers toward the player's real shots. With n shots x₁ … xₙ, starting average d, starting spreads s₀ (short) and l₀ (long), and weight k = 5:

| Value | How |
|---|---|
| Average a | (k·d + Σx) / (k + n) |
| Short spread | √((k·s₀² + 2·Σ(a − x)²) / (k + n)), the sum over shots shorter than a |
| Long spread | √((k·l₀² + 2·Σ(x − a)²) / (k + n)), the sum over shots longer than a |
| Shots | n |

- The 2 is there because each side gets only about half the shots.
- The average and both ends of the range are rounded to whole yards at the end.
- One wild shot or bad GPS spot moves the numbers only a little, and less as shots add up.

A driver at 230 in the bag, and a player who averages 256 with it:

| Shots | Average |
|---|---|
| None | 230 |
| 5 | 243 |
| 20 | 251 |
| 50 | 254 |

Changing a club's distance in the bag changes its starting average. With few shots that moves the numbers a lot; with many, barely. The bag's distances are never changed by shots; they stay the player's starting numbers.

### Club guesses

Club guesses pick by the Caddie average instead of the bag distance. `ClubGuess` does not change; it is handed the bag with each club at its Caddie average. Until a club has shots, that is its bag distance, so guesses work as today.

### When it is worked out

| Worked out | Not worked out |
|---|---|
| At launch | On every redraw |
| A round ends | A change to the round in progress: its shots don't count yet |
| A past round is edited or deleted, or rounds arrive from iCloud | |
| A club goes in or out of the bag, or a bag distance changes | |
| The Green Zone setting changes | |

### Screen

`CaddieView`, titled "Caddie". One row per club in the bag, in bag order, putter left out. Clubs out of the bag are not shown, even with shots.

```
Driver                                243 yd
5 shots
──────┼──────┼──────┼──────┼██████●███┼──
                                 223  264

7 Iron                                148 yd
22 shots
──────┼──────┼──────┼██●███──┼──────┼──
                   130  160

Lob Wedge                              75 yd
No shots yet
──────┼─█●█──┼──────┼──────┼──────┼──
      66  81
```

- Club name on the left, with the shot count under it ("1 shot", "14 shots"). Average on the right in a larger font.
- A line across the full width of the row, with a tick every 50 yards. Every row shares one scale, from 0 to the longest club's high end rounded up to the next 50 yards, so the bars step down through the bag and gaps and overlaps between clubs show. That helps the player see a club they could take out of the bag.
- On the line, a bar from the low end of the range to the high end, with a dot at the average. The low end's number is under the bar, ending at its left end; the high end's starts at its right end, so the two never overlap.
- A club with no shots: its starting estimate, with the bar in a lighter color and "No shots yet" in place of the count.
- No clubs but the putter in the bag: an empty screen, "No Clubs", "Add clubs to your golf bag in Settings to see how far you hit each one."
- Footer: "Starts from your golf bag's distances and moves toward your own shots: each shot's spot to the next. The bar shows where about two in three shots land. Putts, thumbs-down shots, shots from the Green Zone and shots with penalty strokes are left out."

### Club Distances screen

Settings › Golf Bag › Distances keeps editing the bag's distances, which are now the starting numbers. It gets a footer: "Where each club starts. The Caddie moves it toward your own shots as you play."

## 4. Code

| Piece | Where | Does |
|---|---|---|
| `HomeView` | `SpotGolf/Views/Home` | Holds the active tab, shows its screen, the tab bar as a bottom safe area inset, the navigation bar items, and the alerts now on the round list (update notice, sync error) |
| `HomeTab` | `SpotGolf/Views/Home` | The five tabs: icon, label |
| `HomeTabBar` | `SpotGolf/Views/Home` | The bar |
| `RoundListView` | `SpotGolf/Views` | The list only, with its swipe actions, delete alert and export |
| `CourseSelectionView` | `SpotGolf/Views` | Gets a tab form without its own navigation stack or Cancel |
| `SettingsView`, `PuttDataSharingView` | `SpotGolf/Views` | Lose their navigation stacks and Done buttons |
| `ShotDistances` | `SpotGolf/Utilities` | Lists each club's counted shots, in yards, from rounds and the Green Zone. Unit tested |
| `ClubDistance` | `SpotGolf/Utilities` | One club's average, range and shot count: its starting estimate blended with its shots. Unit tested |
| `CaddieStore` | `SpotGolf/Services` | In `PhoneServices`. Holds each club's `ClubDistance` and `guessBag`, the bag with each club at its Caddie average. Works them out again at the times in "When it is worked out" |
| `SpotActions`, `SpotEditSheet` | `SpotGolf/Views/RoundMap` | Hand `services.caddie.guessBag` to club guesses instead of `services.golfBag.bag` |
| `ClubDistancesView` | `SpotGolf/Views` | The footer |
| `CaddieView` | `SpotGolf/Views/Caddie` | The screen |
| `Scorecard`, `ScorecardFill`, `DriverHead`, `PutterHead`, `PutterHeadFill` | `Assets.xcassets` | The tab icons, template images |

## 5. Tests

| Test | Checks |
|---|---|
| `ShotDistancesTests` | Spot-to-next yards; each rule in "Which shots count" |
| `ClubDistanceTests` | No shots gives the starting estimate (230 gives 202 to 248); the driver table above; short and long spreads from shots on each side; rounding |
| `CaddieStoreTests` | `guessBag` has the Caddie averages and no distance for the putter; it changes when a round ends, a bag distance changes and the Green Zone changes; a round in progress changes nothing |
| `OutsideRoundUITests+Caddie` | The Caddie tab shows a row per bag club and no putter; the past round's clubs show their shot counts, the rest their bag distance and "No shots yet" |
| `OutsideRoundUITests+Tabs` | Each tab shows its screen; the bar stays put while the round list scrolls |
| Existing UI tests | Leave Settings and Putt Data Sharing by tapping the Rounds tab instead of Done |
| `RoundStartUITests` | New Round starts from the + tab; + during a round opens the map |

## 6. Sources

| Source | Used for |
|---|---|
| Shaw et al. (2023), [Within- and between-session reliability of golf swing variables using the TrackMan launch monitor in talented golfers](https://figshare.cardiffmet.ac.uk/articles/journal_contribution/Within_and_between-session_reliability_of_golf_swing_variables_using_the_Trackman_sup_sup_launch_monitor_in_talented_golfers/23999727), *Journal of Strength and Conditioning Research* 37(12) | Carry varies 5.8% or less shot to shot for skilled golfers on a launch monitor |
| MyGolfSpy, [The Stock Yardage Myth](https://mygolfspy.com/news-opinion/instruction/the-stock-yardage-myth-how-often-amateurs-actually-hit-their-number/), from Shot Scope on-course data | Share of 7 iron shots within 5 yards of the player's own average, by handicap |
| HackMotion, [Shot Dispersion in Golf](https://hackmotion.com/shot-dispersion-in-golf/) | Short-to-long spread by handicap. It cites no data, so it is only a check |
| Broadie and Ko (2009), [A simulation model to analyze the impact of distance and direction on golf scores](https://business.columbia.edu/sites/default/files-efs/pubfiles/4703/wsc_golf_broadie_ko.pdf) | Distance error is about the same share of the distance over 60 yards, larger for weaker golfers, and skewed short by mishits |
| Broadlands round, 2026-10-26 (`Data/Simulations`) | Check against a real round: 4 driver shots of 242 to 272 yards and 3 seven wood shots of 199 to 223, each inside the starting range around its own average |
