# Putt detection in rounds

The watch detects ball contact from the accelerometer and the microphone, records each contact in the round's stream, and the phone turns contacts into putt suggestions. The numbers come from the captures in `2026-10-06-putt-capture.md`.

## 1. When the detector runs

| Event | Action |
|---|---|
| A GPS fix puts the watch within 30 m of the display hole's green (`HoleShape.chipZoneMargin`), with the workout running | Start the mic, then device motion and the detector on every accelerometer batch. If the mic will not start, or its permission is missing, nothing starts and the next try is a minute later |
| The workout stops | Stop them |
| Fixes stay beyond 30 m for 10 s | Stop them |
| `HoleAdvancer` moves the display to the next hole | Stop them; the zone is now the next hole's green |
| The round ends | Stop them |

The accelerometer is already running for `SwingDetector`. Measured on the four rounds in `Data/`, the zone covers 67 to 83 minutes a round; the mic, both sensors and the detector's math cost under 3 battery points an hour.

## 2. How it works

### Watch: the contact score

For every accelerometer reading `k` (800 a second):

| Step | Formula | Constant |
|---|---|---|
| Burst | `burst = √(bx² + by² + bz²)`, `bx = x(k) − mean(x(k−4)…x(k+4))`, same for y, z. Skip the reading when `burst < 0.05 g` | `burstWindow = 9`, `minBurst = 0.05 g` |
| High-passed audio | `h(n) = a(n) − a(n−1)` for each audio sample | |
| Level | `level(m) = √(mean(h²))` over each millisecond `m` (48 samples) | |
| Background | Median of `level` over the previous 10 s | `backgroundWindow = 10 s` |
| Click | `click = max(level(m) : |t(m) − t(k)| ≤ 4 ms) ÷ background` | `clickWindow = 4 ms` |
| Score | `score = burst × click` | |
| Onset gate | `level(m) ÷ max(level 2 to 6 ms before m) ≥ 4`, background as the divisor's floor | `minOnset = 4` |
| Turning gate | Mean rotation rate over the 100 ms before `t(k)` `≥ 0.4 rad/s` | `minTurning = 0.4` |
| Contact | Both gates pass and `score ≥ 1.2`. The strongest reading within 1 s is the event | `minRecordedScore = 1.2`, `contactSpacing = 1 s` |

`t(k)` is `CMAccelerometerData.timestamp`; `t(m)` comes from the audio buffer's `AVAudioTime.hostTime`. Both are on the uptime clock and agree within 1 ms. Readings within 1 s of a tap on the app's own buttons are skipped.

| Inputs | Source | Rate |
|---|---|---|
| x, y, z | batched accelerometer | 800 Hz |
| rotation rate | batched device motion | 200 Hz |
| a(n) | `AVAudioEngine` input tap, `.record`, `.measurement` | 48 kHz mono |

Examples from the outdoor capture:

| | Burst, g | Click | Score | Onset | Turning | Result |
|---|---|---|---|---|---|---|
| Putt at 141.4 s | 0.290 | 125 | 36.3 | 125 | 1.5 | recorded |
| Soft putt at 765.0 s | 0.197 | 9.4 | 1.85 | 8.7 | 0.5 | recorded |
| Practice stroke at 319.7 s | 0.109 | 7.2 | 0.79 | 6.2 | 2.7 | score fails |
| Grass brush at 522.7 s | 0.244 | 21 | 5.1 | 1.6 | 1.9 | onset fails |
| Putter set down at 172.4 s | 0.665 | 509 | 338 | 1.1 | 0.2 | both gates fail |

### Watch: the stream record

| Record | Kind byte | Body, little-endian, 24 bytes |
|---|---|---|
| Contact | 2 | milliseconds since 1970 Int64, score Float32, burst Float32, click Float32, turning Float32 |

Swing records are unchanged. Older phones drop an unknown kind: a MINOR version bump. The CSV export gains a `contact` row with columns `score`, `burst` and `click`; the importer reads both headers.

### Phone: putt suggestions

In `StrokeFinder.suggestions`, a contact belongs to the stop it was made in (with `stopSlack`) and sits at the fix nearest in time. For each stop within `chipZoneMargin` of the green with no full swing:

| | Rule | Constant |
|---|---|---|
| 1 | **Long putt.** Each contact with `score ≥ 2.7` is a putt suggestion at its own time and spot, unless a stronger contact is within 5 s of it | `puttScore = 2.7`, `sameStrokeGap = 5 s` |
| 2 | **Tap-in.** After a rule-1 putt in the same stop, the first contact with `score ≥ 1.2` at least 5 s later, and at least 5 s before the next putt (so it is not that putt's practice stroke), is a putt suggestion. Contacts under 2.7 count nowhere else | `tapInScore = 1.2` |
| 3 | **Stop.** A stop with no putt from rules 1 and 2 is offered as today when it lasts `minStop` or longer; weak contacts alone say nothing either way. A stop with a putt gets no stop suggestion | `minStop` |
| 4 | Swings of 3 to 10 g in the zone are no longer offered as putts | removes a rule |
| 5 | A stop with a full swing keeps the full-swing rules. Its contacts more than 5 s after the last full swing go through rules 1 and 2: the putts after a chip from the same spot. It gets no stop suggestion | `sameStrokeGap` |
| 6 | `maxPerHole` applies to putts and stops; full swings are never cut | unchanged |

```
stop in the zone
 ├─ full swing ────────────► full-swing rules
 ├─ contact ≥ 2.7 ─────────► putt (rule 1)
 │    └─ later contact ≥ 1.2 ► tap-in (rule 2)
 └─ no contact, ≥ minStop ─► stop (rule 3)
```

A new `StrokeSuggestion.Kind`, `.contact(score:)`, shows on the map with its own icon and converts to a stroke like a swing. Its ID comes from the contact's time.

## Checks

1. A replay test runs the Swift detector over the two captures in `Data/`: 15 of 15 putts and 0 of 15 practice strokes indoors; 29 of 41 putts, 1 of 14 practice strokes and 0 of 8 grass brushes outdoors (`analyze-capture.py` lets one brush over at 2.8 with its capture-wide background; the rolling background keeps it under). Skipped when `Data/` is missing.
2. Putt Lab shows contacts live, to check the watch against the marks on a green.
3. A round: contacts on the map, the mic's zone time and the hole-change stops in the log, battery against a round without it, no contact or swing from tapping the hole arrows.

## Steps

1. `ContactDetector` in `Shared/`, pure functions over sample arrays, with the replay test.
2. Watch: zone, sensors, mic, the contact record, the tap guard.
3. Phone: receive and export contacts; rules 1 to 4 with tests; the suggestion kind and icon.
4. Putt Lab live contacts.
5. A round, then thresholds revisited with its data.
