# Putt capture

Raw sensor recording on the watch, to find which signals tell a real putt from a practice stroke, a waggle, or standing on the green. Putts are 3 to 7 g on the accelerometer (see `2026-10-04-full-swing-strokes.md`), the same as fidgets, so the peak force alone can't find them. The guess is that ball contact shows as a short click on the microphone and a sharp stop in the wrist's rotation, while a practice stroke has the swing but no click.

## What is recorded

A capture is started and stopped on the watch's Putt Lab page, with no round running. While recording, the page shows only buttons: text that changes makes the screen jump on the wrist. It needs a workout, since `CMBatchedSensorManager` only delivers during one; the watch starts and ends one itself.

| Signal | Source | Rate | File |
|---|---|---|---|
| Accelerometer x, y, z in g | `CMBatchedSensorManager` accelerometer | 800 Hz | `accel.bin` |
| Rotation rate x, y, z in rad/s; user acceleration and gravity x, y, z in g; attitude quaternion x, y, z, w | `CMBatchedSensorManager` device motion | 200 Hz | `motion.bin` |
| Microphone | `AVAudioEngine` input tap, `.record` category, `.measurement` mode | The mic's own rate, mono 16-bit PCM | `audio.wav` |
| Marks: the player's labels | Buttons on the watch | | `marks.csv` |
| Capture details | | | `meta.json` |

Marks are tapped after the stroke, so a mark means "a stroke of this label happened in the seconds before it":

| Button | Label | Meaning |
|---|---|---|
| Putt | `putt` | The ball was struck |
| Practice | `practice` | A practice stroke with no ball |
| Practice ground | `ground` | A practice stroke with no ball that hit the ground |

A tap gives a haptic and a "Putt recorded" screen with Undo, which goes away on OK or after 4 s. Undo takes the last mark out of `marks.csv` and `meta.json`.

Anything not marked is noise: walking, picking up balls, reading the green.

## Files

Every time is seconds since the capture started, on the device's uptime clock (the one `CMAccelerometerData.timestamp` uses). `meta.json` gives the start as a date and as uptime, so times convert to dates.

| File | Layout |
|---|---|
| `accel.bin` | Records of 20 bytes, little-endian: `t` Float64, then `x y z` Float32 |
| `motion.bin` | Records of 60 bytes, little-endian: `t` Float64, then 13 Float32: rotation rate `x y z`, user acceleration `x y z`, gravity `x y z`, quaternion `x y z w` |
| `audio.wav` | Standard WAV. `meta.json` gives `audio.startTime`, the capture time of sample 0, and `audio.sampleRate` |
| `marks.csv` | Header `t,label,date`, one row per mark, appended as they happen |
| `contacts.csv` | Header `t,score,burst,click,turning`: the contacts `ContactDetector` found as the capture ran, the same detector a round runs, so the page's live count and haptics can be checked against the marks |
| `meta.json` | `id`, `version`, `startDate`, `startUptime`, `endDate`, `duration`, `audio` (`sampleRate`, `channels`, `startTime`, `startHostTime`, `startUptime`), `accelCount`, `motionCount`, `audioFrames`, `startBattery` and `endBattery` (0 to 1, to see what recording costs), `marks` |

The audio start comes from the first buffer's `AVAudioTime.hostTime`, which is on the same clock as uptime. The uptime read in that callback is kept too, so a mismatch would show.

## Getting the data off the watch

```
Watch                                   Phone
Stop capture
  → WCSession.transferFile each file  → stored in Documents/captures/<id>/
  ← transfer finished: file deleted
Settings → Putt Captures → share one capture as <id>.zip (AirDrop to the Mac)
```

Transfers continue with the app in the background. Files that failed are queued again when the watch app launches or a capture stops.

## Analysis

`analyze-capture.py <capture.zip or folder>` prints the capture's details, the real sample rates, and for each mark the strongest accelerometer reading, rotation rate and sound in the 8 s before it, plus every sound and motion peak that is not near a mark. The first question is whether the click is there for every `putt` and absent for every `practice`.

## Captures of 2026-10-06

| | Indoor, `Data/putt-capture-2026-10-06T162828.zip` | Outdoor, `Data/putt-capture-2026-10-06T172603.zip` |
|---|---|---|
| Length | 226 s | 948 s |
| Marks | 15 putts, 15 practice | 41 putts, 14 practice, 8 ground |
| Wait before the mark | about 1.5 s | 2 to 3 s |
| High-passed audio background | 0.000016 | 0.000021 |
| Battery | | 75% to 70%: 19 points an hour, with the screen on for 63 taps |

Both batched sensors ran together, and the mic recorded the whole time with the wrist down. The 91 MB outdoor audio took about 20 minutes to reach the phone over Bluetooth, and the watch's "sending" count stayed stale until the app was next opened.

### What a putt looks like

Ball contact is a click and a high-frequency accelerometer burst at the same instant. Neither alone is enough, and neither is the peak force or rotation:

- Putts peak at 1.3 to 1.5 g with gravity included, under half the swing detector's 3 g. Practice strokes are the same.
- Outdoors, wind raises the raw audio background four times and gusts reach 0.05 of full scale, so raw loudness means nothing. Wind lives below a few hundred Hz and the click above, so the audio is high-passed first (each sample minus the one before), after which the background is the same indoors and out.
- The accelerometer's sharpest single change (jerk) worked indoors but not outdoors, where practice strokes on grass make as much. The burst (each axis minus its 11 ms moving mean) with the click at the same instant is what holds up.

The contact score in `analyze-capture.py` is the largest burst × click product in the stroke's window, click as a multiple of the background, with two gates: the click must rise sharply (4 times what it was 2 to 6 ms earlier) and the wrist must be turning (0.4 rad/s or more in the 100 ms before).

| Score, gated | Indoor putts (15) | Indoor practice (15) | Outdoor putts (41) | Outdoor practice (14) | Outdoor ground (8) |
|---|---|---|---|---|---|
| Median | 13.3 | 0 | 6.5 | 0.6 | 0.8 |
| Range | 3.2 to 657 | 0 to 0.9 | 1.2 to 444 | 0 to 2.6, and 23 | 0 to 2.8 |
| Over 2.7 | 15 | 0 | 29 | 1 | 1 |

What the shapes showed, and what the player said about the session:

- Ball contact has an instant attack: the click reaches its peak within 1 to 2 ms, for hard and soft putts alike, and the burst lasts 20 to 45 ms. The putter slows a little after it.
- Two "practice" strokes scored like the hardest putts before the gates. Their clicks rose over 18 and 47 ms and the wrist was nearly still (0.2 rad/s), so they were not strokes: something like the putter set down or bumped. The player recalls every practice stroke as a real one, which fits. The gates drop one of them; the other, at 899 s, has a sharp onset and the wrist turning at the gate's edge, and stays as the one false positive.
- The grass brushes rose over 29 to 93 ms: scrapes, not clicks. Without the gates 3 of 8 crossed the line; with them, 1 borderline one does. The player says none were sharp or hard.
- The 12 putts under the line are the short, soft ones: the run from 759 to 813 s was a group of balls putted at each other. Their clicks are 8 to 21 times the background with a sharp onset, and their bursts 0.1 to 0.25 g; the loudest practice clicks reach 19 times. There is no line that takes those putts without taking practice strokes too.
- Tapping the watch screen makes a 2 to 3.6 g reading and a burst of 2 g or more, bigger than any stroke. In a round, taps on the hole arrows can pass the 3 g swing threshold.

### Battery test

The Putt Lab page has two switches. **Microphone** off runs the sensors alone. **Save data** off is a battery test: the sensors and the mic run, the watch does the detector's math on every batch (the 11 ms burst and the high-passed click energy) and writes nothing but the counts and the battery levels, which is what a round would do. The phone's capture list shows the drop in points per hour.

The test is two captures of 20 minutes or more each with the watch on the wrist and the screen left alone, one with the mic off and one with it on. The difference is the mic's cost; the mic-off one is close to a round's load without GPS.

Result, mic on, 2026-10-06 (`Data/putt-capture-2026-10-06T200712.zip`): 20.3 minutes with the accelerometer at 801 Hz, device motion at 200 Hz, the mic taking 20.1 minutes of 48 kHz audio, and the burst and click math on every batch. The battery read 50% at the start and 50% at the end: under one point, so under 3 points an hour. At 20 to 40 minutes of stopped time on greens per round, the mic costs at most 1 or 2 points a round on a Series 9. The 19 points an hour of the outdoor capture was the lit screen and the 125 KB/s of files, not the sensors. Battery is not a reason to leave the mic out.

### Next

- Soft putts are the open problem. Options: a lower line when the stroke is slow and short, since a tap-in has a small backswing; or accept that a tap-in on the green is found another way, since the player stays at the hole and walks off.
- Try the rotation shape of the stroke as a third signal, to separate a ground strike from a putt.
- Decide where detection runs. The accelerometer burst is on the watch in a round today; the mic is not, and the battery test says it can be, on only while the player is stopped on or near the green.
