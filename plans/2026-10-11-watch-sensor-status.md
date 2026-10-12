# Watch sensor status and hard restart

At Legacy Ridge on 2026-10-09 the watch's accelerometer died for the whole round and nothing on the watch showed it (`plans/2026-10-10-sensor-repair.md`). The End Round page now shows whether the accelerometer is alive, and has a button that restarts everything by hand, for a failure the repair ladder does not catch.

## End Round page

```
Over 10 g at     2:34:05 PM
Force                17.3 g
[ ↻ Restart Sensors ]
[ End Round ]
```

- The time and magnitude are the last accelerometer reading over 10 g. A swing is 17 to 22 g, so a stale time means the accelerometer is dead. The time is the local time of day alone.
- With no reading since launch the time reads `None` and the force `—`.
- The time and magnitude are not saved; a relaunch starts over.

## Hard restart

```
Restart Sensors
  ─▶ SensorInputs.restartAll: every running input stops and starts on a fresh manager,
     its watchdog starts over, and a microphone waiting out a refusal is tried now
  ─▶ LocationManager.restartUpdating: location updates stop and start
  ─▶ WorkoutManager.forceRestart: the session ends and a new one starts when it has ended,
     with no rate limit; a session that is not running, or none, is started right away
       workout running again
  ─▶ the subscribers' inputs start again on fresh managers, as after a stall
```

| Where | Change |
|---|---|
| `SensorInputs` | `lastHighG`, the last accelerometer reading over `highGThreshold` (10 g), for the screen. `restartAll(reason:)` |
| `WorkoutManager` | `forceRestart(reason:)`, which skips the 2 min limit and clears a wait for the foreground |
| `LocationManager` | `restartUpdating()` |
| `WatchServices` | `hardRestartSensors()` runs the three and records a `hardRestart` event |
| `StreamEvent` | `hardRestart` (50). `workoutRestart` value 4: forced by the user |
