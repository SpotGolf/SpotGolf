# Sensor repair

On the Legacy Ridge round of 2026-10-09 the watch recorded 17,598 GPS fixes and no swing or contact in five hours, while a SpotGolf golf workout ran from 09:58 to 14:52 (Fitness app). The same build detected 17 to 22 g swings at home that evening, with the watch app on screen and with it in the background. The accelerometer stream died or never started, and nothing in the app repaired it: `SwingDetector`'s watchdog restarts the same `CMBatchedSensorManager` every 10 s forever, and `WorkoutManager` never hears that the stream is dead. The watch's log had rolled over by the evening, so the first failure is not known. This change adds a repair ladder and writes the watch's sensor events into the round's stream, so the next failure can be read from the phone's store.

## One owner for the sensors

The `feature/sensor-inputs` refactor of 2026-10-07 is applied here by hand (it forked before the Swift 6, Observation and SwiftData moves, so it does not merge). `SensorInputs` owns the accelerometer, device motion and the microphone. `SwingDetector`, `ContactMonitor` and `PuttCaptureRecorder` subscribe to the streams they need and never touch a sensor; an input runs while anyone subscribes and stops when the last subscriber cancels. `TapGuard` lives there too. `MicrophoneInput` restarts itself after an audio interruption or configuration change, and the capture's WAV writing moves to `CaptureAudioWriter`.

```
SensorInputs ──accelerometer──▶ SwingDetector
             ├─accelerometer──▶ ContactMonitor ◀── device motion, microphone
             └─all three──────▶ PuttCaptureRecorder
```

## Repair ladder

```
an input errors, or sends nothing for 10 s
  ─▶ 1. SensorInputs restarts it on a NEW CMBatchedSensorManager (or restarts the mic)
        3 restarts in a row with no data
  ─▶ 2. SensorInputs reports a stall; for a batched sensor, WorkoutManager ends the
        session and starts a new one (at most once per 2 min)
        workout running again
  ─▶ 3. the subscribers' inputs start again on fresh managers
```

| Where | Change |
|---|---|
| `RestartWatchdog` | Counts restarts in a row with no data since the previous start (`restartsWithoutData`). `isStalled` is true at 3; `stallReported()` resets the count so a stall that goes on fires again |
| `SensorInputs` | One watchdog per input. A batched sensor restarts on a new manager. `onStalled(input)` when the watchdog says stalled. `onEvent` reports the sensor events below |
| `WorkoutManager` | `restart(reason:)` ends the running session and starts a new one when it has finished ending, rate-limited to one forced restart per 2 min. `checkWorkout` also compares `isRunning` with `session.state`: a session not running while the flag says running, or the reverse, corrects the flag, which starts or stops swing detection through the existing listener. `onEvent` reports the workout events below |
| `WatchServices` | Wires `sensors.onStalled` (not for the microphone) to `workoutManager.restart(reason:)`, and every `onEvent` to `watchSync.record(event)` |

A forced restart saves one golf workout and starts another, so the Fitness app shows two for the round. That is accepted.

## Stream events

A fourth stream record kind. Older phone builds skip records of an unknown kind, so nothing else changes in the sync.

| Field | Bytes |
|---|---|
| kind | 1: `3` |
| timestamp | 8: milliseconds since 1970, Int64 |
| code | 2: UInt16, below |
| value | 4: Float32, meaning per code, 0 when unused |
| padding | 10: zero |

| Code | Name | Value |
|---|---|---|
| 1 | `workoutStarted` | |
| 2 | `workoutRecovered` | session state |
| 3 | `workoutState` | new session state (`HKWorkoutSessionState`) |
| 4 | `workoutError` | `HKError` code |
| 5 | `workoutRefused` | retry delay in seconds |
| 6 | `workoutRestart` | 1 restart by the watchdog, 2 forced by a stall, 3 flag corrected |
| 7 | `workoutEnded` | |
| 10 | `swingDetectionStarted` | |
| 11 | `swingDetectionStopped` | |
| 12 | `accelerometerFirstBatch` | readings in the batch |
| 13 | `accelerometerError` | `CMError` code |
| 14 | `accelerometerRestart` | restarts in a row with no data |
| 15 | `accelerometerStalled` | restarts in a row with no data |
| 16 | `accelerometerUnsupported` | |
| 20 | `contactsOn` | hole number |
| 21 | `contactsOff` | seconds on |
| 30–34 | `deviceMotion…` | as 12–16, for device motion |
| 40 | `microphoneStarted` | |
| 41 | `microphoneError` | 1 permission missing, 2 the start failed |
| 42 | `microphoneRestart` | restarts in a row with no data |
| 43 | `microphoneStalled` | restarts in a row with no data |

- `WatchSync.record(_ event:)` appends the event to the active round's stream. With no active round it keeps the last 50 events, and writes those from the last 5 minutes into the stream when a round starts, so the workout start that comes before the round is kept.
- Phone: `StreamStore.events(for:)`. `TrackExporter` writes one `event` row per event, with the code name in the `strokeType` column and the value in `peakG`; the importer already skips unknown row types.
- No UI. The phone's store or a CSV export is read with a script.

## Version guard

On 2026-10-10 the phone had the new build and the watch still had the old one (watchOS keeps a watch app whose version has not changed), and a test round was run on the pair before that was noticed. From now on the two apps refuse to record together on different versions, and versions change with every build that goes on a device.

- `StartRound.version` is the phone app's version (`AppVersion.text()`, now in `Shared`). A phone from before this sends none, which is read as `""`.
- The watch compares it with its own version first, before permissions. On any difference it replies `StartRoundRefused` with `reason: .versionMismatch(watchVersion:)`. `StartRoundRefused.reason` is an enum; the wire keeps `missing` (empty for a version refusal) so an older phone still reads the refusal, and adds `watchVersion`.
- The phone's start state becomes `needsWatchUpdate(watchVersion:)`, and the start banner says "Install SpotGolf 0.6.0 on your Apple Watch. The watch has 0.5.0." with Retry and Cancel.
- A watch app from before this ignores the version and accepts the round, as before.

## Out of scope

- A swing still in its peak window when the round ends is flushed after the round's status has changed, so `record` drops it. At most one swing within 3 s of the end is lost.
- The first failure's cause. The next failed round carries its own evidence.
