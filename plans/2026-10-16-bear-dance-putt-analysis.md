# Putt detection: what the Bear Dance round shows

The Putt Lab capture of the Bear Dance round on 2026-10-13, a scramble, checked against the player's marks to find what tells a putt from everything else on a green. The labels, the scripts and a plot of every putt are in `Data/putt-captures/42A9900B-FEF0-4F98-8487-B0BFCE400C64/analysis/` (git-ignored, see its README).

## Summary

- The watch heard every one of the player's 31 putts. The problem is the 177 other contacts beside them, and the phone turned 89 of those into putt suggestions.
- The wrist's motion before the contact separates putts from nearly everything else: a still address, a small backswing, and the wrist back at its address tilt when the ball is hit. A gate built on that keeps 31 of 31 putts and 1 of 177 false contacts. It does not depend on how the watch is worn.
- The mic is still needed. Without it, practice strokes that brush the grass, haptics and taps pass the gate.
- The round was a shotgun start on hole 9, which the app does not support yet. The watch did not move from the 18th to the 1st, so hole 1 was never recorded, and the phone cannot place holes 1 to 8 played after the 18th.
- Several pipeline bugs cost putts on their own. The phone's rules dropped 6 putts the watch had heard.

## The data

| | |
|---|---|
| Segments | 24, one per green visit, 65.8 minutes, 487 MB |
| Green Zone | 15 m (the round's setting) |
| Putt marks | 27 (not 31) |
| Player putts | 31: 27 marked, 4 never marked (holes 9, 14, the first putt on 18, the second on 15) |
| Watch contacts | 208 in `contacts.csv`, 213 in the phone's stream |
| Holes lost | Hole 1: a shotgun start on hole 9, and the watch did not move from the 18th to the 1st |
| Other sources | The round's stream and logs from the phone's store; the 2026-10-06 indoor and outdoor captures and Broadlands 2026-10-12 as a held-out check |

Three labelers worked independently: one from the sound and the burst, one from the wrist's stroke, one blind to the marks. They agreed on all 31 putts. The blind one found all 27 marked putts and the 4 unmarked ones before it looked at the marks, with 1 false pick.

Marks came 2.2 to 30.7 s after the putt, median 4.0 s. 8 of 27 came 10 s or more late.

## Today's result

| Stage | Putts found, of 31 | False |
|---|---|---|
| Watch contacts, score 1.2 or more | 31 | 177 |
| Watch contacts, score 2.7 or more | 28 | 132 |
| Phone putt suggestions | 25 | 89 |

The 177 false contacts:

| Class | Count | What |
|---|---|---|
| Wrist raise | 75 | Turning the wrist to look at the watch, holding a ball or the flag |
| Wrist moving | 52 | Other arm movement with a click at the same moment |
| Walking | 16 | |
| Knock | 14 | Putter or ball knocks, 0.8 g and up |
| Mark tap | 7 | Touching the screen to mark; Putt Lab only |
| Haptic | 5 | Putt Lab's own contact haptic (see bugs) |
| Other | 8 | Chips, riding in the cart, an impact with the wrist still |

Half of the false phone suggestions score 10 or more, so no score line separates them.

The phone missed 6 putts:

| Putt | Why |
|---|---|
| Hole 12, hole 2, hole 8 | A swing of 10 g or more later in the same GPS stop counts as a full swing and drops every contact before it. All three were on the green: a 37.8 g knock and two wrist shakes |
| Hole 17 twice, hole 5 | Scores 1.36, 1.73 and 2.34, under the 2.7 line |
| Hole 5 | A haptic-caused contact (score 95.8) 2.35 s earlier was stronger, so the putt was merged into it |

## What a putt looks like

All 31 putts fit one pattern. Practice strokes have the same stroke and no ball.

| | Putts (31) | Practice strokes (52) | False contacts (177) |
|---|---|---|---|
| Stillest 0.5 s in the 3 s before | 0.02 to 0.12 rad/s | the same for the first stroke of a series | median 1.69 rad/s |
| Backswing | 0.47 to 0.71 s, 3.4 to 26 degrees | bigger, median 17 degrees, often in a series of 1 to 5 | none or wrist lifts |
| Contact | 0.25 to 0.34 s after the top of the backswing, when the wrist is back at its address angle (-9 to +30 ms) | no burst over 0.03 g | at random points |
| Wrist burst | 0.19 to 1.77 g, 21 to 36 ms long | | |
| Click | Peaks within 1 ms; the burst peaks 7 to 17 ms after it | none | |

See `signature.png` in the analysis folder.

- 17 of 31 putts came after 1 to 5 practice strokes, the last 2 to 5 s before. 14 had none, so practice strokes cannot be required.
- The player's own putts were never closer than 9.6 s apart. In the scramble, other players putted between them.
- Other players' putts are heard (click 20 to 86 times the background, louder than his tap-ins) but give a wrist burst of 0.025 g or less. The burst already keeps them out.
- Score grows with stroke speed to the power 2.8. Half the speed gives a seventh of the score, which is why tap-ins score low. Wind adds to it: tap-in clicks were only 10 times a background raised by wind.
- The ball dropping in the cup is not usable. Speech, other players' putts and ball handling make the same sounds, and no delay repeats.

## The stroke gate

A contact counts only when the wrist's motion before it passes three tests. They use only the 200 Hz device motion up to the contact, and only sizes and angles, never a direction in the watch's frame. So they give the same answer however the watch is worn, and for a left-handed player.

| Test | Rule | Limit |
|---|---|---|
| Still address | Over every 0.4 s window in [t − 3.0, t − 0.5], the mean of the rotation rate's size. The stillest window is the address | 0.30 rad/s or less |
| Back at address | Angle between gravity over the address window and gravity over [t − 0.02, t] | 5 degrees or less |
| Backswing | Impact axis e = the mean rotation vector over [t − 0.04, t]. Over the 1.5 s before, the last rotation about e that is negative, and the lobe it belongs to, integrated | 2.5 degrees or more |
| Return to address (timing) | From the top of the backswing, integrate the rotation about e until it reaches the backswing angle | contact −50 to +60 ms from that moment |

The first three are Gate A. With the timing test it is Gate A+R.

| | Bear putts | Bear false | Older putt windows | Older practice | Older ground | Older events outside any window |
|---|---|---|---|---|---|---|
| Today, score 1.2 | 31/31 | 177 | 46/58 | 1/27 | 1/8 | 17 |
| Gate A | 31/31 | 1 | 44/58 | 0/27 | 0/8 | 1 |
| Gate A+R | 31/31 | 0 | 44/58 | 0/27 | 0/8 | 1 |

- The 2 older putt windows lost had a wrist lift as their contact, not the putt. The putt itself never became a contact, so the gate lost no putt.
- The one Bear false contact under Gate A is a stroke 7 m off green 13, at the spot of a real chip. It hits 162 ms past address, so the timing test stops it.
- The one older event outside the windows comes 1.1 s after a mark: the wrist held up still while marking, then lowering. It passes both gates.

Margins:

| Test | Limit | Worst putt, Bear | Worst putt, older | Nearest non-putt only this test stops |
|---|---|---|---|---|
| Still | 0.30 rad/s | 0.10 | 0.19 | 0.45 |
| Back at address | 5 degrees | 2.3 | 3.2 | 7.1 |
| Backswing | 2.5 degrees | 3.4 (a tap-in) | 5.0 | 0.3 |

Checks that held:

- A re-implementation from the written rules alone matched the reference on all 208 contacts.
- Random rotations and mirrors of the watch frame gave the same decisions on all 208. The labelers' first gate used the player's own posture and axis; under any rotation it kept 0 of 31 putts.
- Leaving out each hole in turn and refitting the limits gave the same 31 and 1. The result is the same for still 0.15 to 0.4, tilt 4 to 7 and backswing 0.5 to 3.
- With the gate on, the watch's recorded-score floor can drop from 1.2 to 0.6 with no added false contact. The first one appears at 0.33.

Weak points:

| Risk | Detail | Fix |
|---|---|---|
| Ground strikes | 5 of 8 older practice strokes that brushed the grass pass Gate A. Only the onset test (4 or more) stops them. The lowest Bear putt onset is 5.0 | Keep the mic and the onset test |
| Chips | A chip by green 9 with an 88 degree backswing passes Gate A+R; only its onset of 2.5 stopped it | Add a limit: backswing 35 degrees or less, or through speed under 3.5 rad/s (putts reached 3.0) |
| Gyro noise | The backswing walk breaks at 0.05 rad/s of added noise. Native noise is 0.002 to 0.004 | Average 5 samples of the rotation about e before the walk |
| Long putts | Tilt at contact grows with backswing size. Device motion lags the accelerometer by about 15 ms (4 to 31). The biggest putts, 23 to 26 degree backswings, fail first if the lag is off by 30 ms | Watch it on long putts. The timing test does not depend on speed |
| Motion gaps | Missing samples at the contact leave the tilt undefined. Bear had no gaps; the 2026-10-06 captures had gaps of up to 20 ms | Resample to a 5 ms grid |
| A restless address | Rocking the putter at 1 Hz by 5 degrees until the takeaway loses most putts | None; it is a miss, not a false suggestion |
| Trail wrist | Not in the data. Frame independence covers how the watch is worn, not a different motion | Capture a round with the watch on the other wrist |
| One player | Every capture so far is the same player and putter | Capture another player |
| Session start | The gate needs 3 s of motion, so a contact in a green session's first 3 s fails. The first putt came 22 s or more after its session started | None needed |

## The impact measure

The detector pairs each burst reading with the click within ±4 ms. The burst peaks 7 to 17 ms after the click, so today's score uses the burst's rising edge.

All rows below use Gate A+R. Phone counts use today's phone rules.

| Impact measure | Bear putts | Bear false | Phone putts / false | Older putts | Older practice | Older ground |
|---|---|---|---|---|---|---|
| Today: click within ±4 ms | 30/31 | 0 | 24 / 0 | 44/58 | 0/27 | 0/8 |
| Click in the 25 ms before the burst | 31/31 | 0 | 27 / 0 | 56/58 | 1/27 | 0/8 |
| Accelerometer only, burst 0.10 g or more | 31/31 | 9 | 7 false | | | 3/8 |
| Burst 0.10 g or more, with the click as a pass/fail check | 31/31 | 0 | 28 / 0 | 58/58 | 0/27 | 0/8 |

- Pairing the click with the burst after it doubles putt scores (1.94 times) and leaves wrist events at 1.00 times. It also brings back the 14 older putts that today's pairing misses: at the burst reading the click has already passed its peak, so onset fails. Without the gate, the new pairing adds false contacts. The two belong together.
- The accelerometer alone is not enough. Its 9 false contacts on Bear are 2 haptics, a chip, a 1.8 g tap with the wrist still, a stroke with no click and a 0.22 g burst, and 4 small events. It also passes 3 of 8 older ground strikes. The mic's onset test rejects all of them.
- The last row's click thresholds were chosen after seeing the data.
- Keep the click as a ratio to the background. An absolute level loses 28 of 56 older putts, because 2026-10-06 was 3 times quieter than Bear Dance. A 4 to 16 kHz band-pass helps tap-ins in wind but costs 3 older putts.
- Starting the mic only at the address does not work. The stroke is known only about 0.1 s after contact, and the click needs 1 s of audio for its background. A mic started by the address posture would save 1 to 2 battery points a round. It would also start the mic 61 to 149 times an hour, against 24 a round today, and one start in 24 stalled this round. Keep the mic on through the zone.

## The phone's rules with gated contacts

| Rules | Putts suggested | False |
|---|---|---|
| Today, ungated contacts | 25 | 89 |
| Today, Gate A contacts | 25 | 1 |
| puttScore 1.2, Gate A | 28 | 1 |
| Every gated contact is a putt, and a 10 g swing drops only contacts within 2 s of it, Gate A | 31 | 1 |
| The same with Gate A+R | 31 | 0 |

With gated contacts:

1. **Every gated contact in a zone stop is a putt.** No score line, no tap-in rule, no stronger-contact-within-5 s rule. The tap-in rule today gives 1 right suggestion for 7 or 8 false ones.
2. **A swing of 10 g or more drops only the contacts within 2 s of it.** Today it drops every contact before it in the stop.
3. **A full swing after a putt in the same stop is not offered.** That removes 3 false full-swing suggestions on greens (37.8, 12.0, 10.2 g). Every 10 g swing on a green this round was a knock or a shake after a putt. The one real chip over 10 g was 15.4 m off. Full swings are grouped before contacts today, so this needs a change in order.
4. **Stop suggestions only where the watch was not listening.** The phone already has `contactsOn` and `contactsOff` in the stream. At 15 m this cuts them from 15 or 16 to 2, both on hole 1. The cost: an 8.5 g chip 7 m off green 13 failed the gate and had only a stop suggestion, which this removes. Keeping a stop suggestion when the stop has a swing of 8 to 10 g would cover it. This round had two such swings in zone stops: the chip and one unexplained 8.3 g swing.

The phone must know which contacts were gated. Suggestions are recomputed, never saved, so a saved round from an older watch would get the new rules too. Applied to this round's ungated contacts, rule 1 would raise its false suggestions from 89 to 136. A gated contact needs its own record kind or a flag, which is a MINOR version bump.

Rules that do not help: one putt per GPS stop (5 of 14 putt pairs shared a stop), requiring the green polygon instead of a margin (loses 4 putts; GPS on greens was off by 3.5 to 11 m), or requiring practice strokes. All 31 putts were inside a phone GPS stop, 0 to 3.8 m from the green's edge.

## Shotgun starts

The round started on hole 9. The app has no shotgun start: holes are always played from the first index to the last.

| What | Effect this round | Where |
|---|---|---|
| The watch never moves from the 18th to the 1st | Hole 1 not recorded: 130 s on its green, 0 heard | `HoleAdvancer.advance()`: `guard nextIndex < orderedHoles.count` |
| The phone's hole timeline only goes up | Holes 1 to 8, played after the 18th, can never get a hole start. Their stops read as hole 12 to 18 and are checked against those holes' greens, so the phone cannot suggest anything for them. That is 15 of the 31 putts | `HoleTimeline.normalized`, `Round.startHole` |

A shotgun start needs more than a wrap. A plain modulo wrap would let a finished round's display jump to hole 1 when the player crosses the 1st tee. The phone's timeline would still drop the starts. A starting hole that rotates `orderedHoles` into play order fixes the watch, the timeline and the Next arrow together. `CourseSelection` is force-decoded, so the new field must be optional. Starting on hole 10 already works by picking the back nine first; only a start inside a nine cannot be set.

## Bugs found

| Bug | Effect this round | Where |
|---|---|---|
| Putt Lab plays an unguarded haptic on every contact | 204 haptics, 6 contacts caused by them (scores 10 to 1130, one a chain), 1 putt merged away | `PuttCaptureRecorder.found()` |
| A ≥10 g swing on the green drops the putts before it | 3 putts | `StrokeFinder.suggestions`, the full-swing drop |
| The tap guard is checked when a 1 s batch arrives, before the tap registers | 2 screen touches became contacts (score 138 and 1.25). 5 more fell 1 to 3 s from the mark, outside the guard's 1 s window; the stroke gate rejects them | `ContactRunner.addAccelerometer` |
| The Set Pin button guards neither its touch nor its `.success` haptic | None seen; it shows only on the green | `WatchRoundView` Set Pin |
| The last contact of a segment is lost from `contacts.csv` | 5 contacts. The stream has them | `ContactMonitor.stop()` sends `.stopped` before the flush; outside rounds `closeSegment` clears the writer first |
| The WAV has no buffer times | The mic stalled on hole 8 (another audio session held it) and 11.4 s went missing with no trace. The WAV clock also drifts 9.55 ppm, 3.5 ms by the end of a long segment | `CaptureAudioWriter` |
| `pull-putt-captures.sh` flags every segment's audio | AVAudioFile writes JUNK and FLLR chunks, so the 44-byte header read finds zeros. Even fixed, a frame count cannot show a mic gap | The check block |
| `meta.json` mark dates are cut to whole seconds | Matching marks to the stream by date is off by up to 1 s. `marks.csv` has milliseconds | `PuttCapture.Mark` |

## Battery

90% to 55% over the round. 20 points over 65.8 minutes of recording on greens, 18% an hour, and 15 points over 211.5 minutes between greens, 4.3% an hour. Recording brings the Putt Lab page to the front and writes 7.4 MB a minute. The 2026-10-06 battery test put the mic and detector math under 3 points an hour, so most of the 18% is the screen and the files.

## Recommendations

```
burst ≥ 0.05 g
 └─ click in the 25 ms before it, onset ≥ 4, score ≥ 0.6
     └─ stroke gate: still address, back at address, backswing ≤ 35°, return to address
         └─ gated contact ─► phone: putt suggestion in a zone stop
```

In order:

1. **Shotgun start.** A starting hole that rotates `orderedHoles`, so the watch advances from the 18th to the 1st and the phone's timeline accepts holes 1 to 8. Without it, a shotgun round loses putts and suggestions after the wrap. Breaking for saved rounds and `StartRound`: MINOR.
2. **Guards.** No contact haptic in rounds. Every haptic goes through one helper that guards it. Guard Set Pin. Check the tap guard again when a contact is reported, not when its batch arrives.
3. **Stroke gate on the watch.** In `ContactDetector`: a 6.1 s ring of device motion (rotation vector and gravity, 38 KB), Gate A+R with a backswing limit and 5-sample smoothing, the click paired with the burst after it, and a score floor of 0.6. `ContactRunner` passes the rotation vector and gravity. A Swift prototype fed this round in 1 s batches matched the Python features on 213 of 213 contacts. It cost 0.9% more detector CPU, and contacts were decided 0.1 to 1.1 s after impact.
4. **Gated contacts on the phone.** A new record kind for gated contacts, then phone rules 1 to 4 above for them only. Older contacts keep today's rules.
5. **Replay test.** This round as a regression test: the 487 MB capture from `Data/`, skipped when missing, and the 19 KB labels fixture checked in. It takes 41 s in Debug.
6. **The next capture.** Putt Lab records each audio buffer's host time, an events file (haptics, taps, screen touch-downs, hole changes, mic restarts), the gate's features for every candidate, the watch's GPS fixes, and the wrist and crown side. Fix the WAV check in `pull-putt-captures.sh` and add a duration check for mic gaps. Fix the flush order.
7. **More players.** A round with the watch on the other wrist, and a round from another player, before the gate's limits are trusted beyond this player.
