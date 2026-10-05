# Missed swings

Swings were not recorded during a round even though every permission was granted. These are all the ways in the code that a swing can go unrecorded. We go through them one at a time.

## Swing detection stops and never restarts (watch)

- [x] **1. Accelerometer error stops detection for the rest of the round.**
  `SwingDetector.swift:29-33` calls `stop()` on an error. The swing observer in `WatchAppDelegate.swift:67-79` only calls `start()` when "round active and workout running" changes, and that value stays true, so detection never comes back.
  *Fix (done):* on an error, stop and start the accelerometer right away, unless it was started less than 10 s ago. In that case item 2's watchdog retries.

- [x] **2. Accelerometer goes quiet with no error.**
  Nothing checks that batches keep arriving (`SwingDetector.swift:28`). Detection looks like it is on but receives nothing.
  *Fix (done):* a watchdog checks every 10 s. If `isAccelerometerActive` is false, or no batch arrived for 10 s, it stops and starts the accelerometer. The rules are in `RestartWatchdog`.

- [x] **3. A failed workout is never restarted.**
  `WorkoutManager.swift:155-162` calls `sessionFinished(restart: false)`, and `WorkoutManager.swift:133-135` gives up. `isRunning` stays false, so detection stays off.
  *Fix (done):* the same `RestartWatchdog` as items 1 and 2, every 10 s, restarts the workout whenever a round needs it and it is not running. A failure with `HKErrorAnotherWorkoutSessionStarted` or `HKErrorBackgroundWorkoutSessionNotAllowed` waits until the app is on screen (`applicationDidBecomeActive`), because watchOS refuses a new workout until then. An end does not restart right away; the watchdog does it, so a failure's error that arrives after the end is seen first.

- [x] **4. A second workout end within a minute is never restarted.**
  `WorkoutManager.swift:126-132` gives up for the rest of the round.
  *Fix (done):* the once-a-minute limit and the give-up are removed; item 3's watchdog retries.

- [x] **5. The workout never reaches the running state.**
  If `HKWorkoutSession` creation throws (`WorkoutManager.swift:80-82`), nothing tries again. If a recovered session is not running (`WorkoutManager.swift:94`), nothing starts it.
  *Fix (done):* item 3's watchdog retries creation, calls `startActivity` on a `.notStarted` or `.prepared` session, and `resume` on a `.paused` one.

- [x] **6. watchOS kills the app in the background.**
  Every batch (about 800 readings a second) is turned into `Reading` values and handed to the main actor (`SwingDetector.swift:36-52`). Heavy main-thread work in the background can get the app killed. Swings are lost until watchOS relaunches the app.
  *Result (not a cause):* measured `SwingPeakFinder.add` at 4.5 µs per batch on average, 27 µs at worst (Mac, 800 readings, an hour of batches). Even 20× slower on a watch, that is about 0.01% CPU. No change.

- [ ] **6a. A workout restart from the background is refused.**
  watchOS refuses a new workout while the app is in the background (`HKErrorBackgroundWorkoutSessionNotAllowed`), so after items 3–5 the workout only comes back once the user raises their wrist and the app is on screen.
  *Fix:* when the watch's workout stops mid-round, the phone restarts it with `startWatchApp`, which launches the watch app with a workout even in the background.

## A detected swing is lost before it reaches the phone

- [x] **7. Swing dropped when the watch has no active round.**
  `WatchSync.swift:45-47`. This should only happen at the start or end of a round.
  *Result (no change):* detection only runs while a round is active, so this only happens for a swing at the moment a round ends.

- [x] **8. The watch deletes the whole stream when the phone doesn't know the round.**
  `StreamSender.swift:88-94`. This can happen if the phone has not saved the round yet, or deleted it. Every GPS fix and swing for that round is lost.
  *Result (no change):* the phone always has a round the watch is sending, including ended and resumed ones. It only answers "unknown" after the user deletes the round, or after the phone loses its saved rounds (a build that can't read `rounds.json`). The first is the user's choice, and the second is our bug, which no fix here can recover from.

- [x] **9. The watch deletes a stream for a round it doesn't know.**
  `StreamSender.swift:117-122`.
  *Result (no change):* the watch deletes a round and its stream together on cancel, and prunes a round only once its stream is gone. A stream without its round only happens when the watch loses its saved rounds, which is the same class of bug as item 8.

- [x] **10. The last swing is thrown away when detection stops.**
  A swing whose 0.5 s peak window has not closed is held in `SwingPeakFinder.current` and is dropped on `stop()` (`SwingDetector.swift:56-61`) and on the next `start()` (`SwingDetector.swift:27`).
  *Fix (done):* `SwingPeakFinder.flush()` returns the pending swing, and `SwingDetector.stop()` passes it to `onSwing`. This matters most on a workout restart (items 3–5), which stops detection mid-round. On a round end the round is already inactive, so the swing is still dropped (item 7).

- [x] **11. Records after the phone's end time are cut.**
  `WatchSync.swift:189`. This is intended, but a wrong clock or an early end tap on the phone would cut real swings.
  *Result (no change):* this is how ending from the phone works. Swings are only lost if End is tapped before the last shot.

## A swing reaches the phone but no suggestion is shown

These rules are in `StrokeFinder.swift:119-173` and `RoundMapView.swift:845-858`.

- [ ] **12. The swing is not inside a GPS stop.**
  A stop needs 8 s within 5 m (`StrokeFinder.swift:16-18`). A quick routine, or watch GPS drift over 5 m, means no stop, so the swing is dropped.
  *Fix:* review. Possible options: widen the radius, shorten the minimum, or place a swing that has no stop at its nearest fix.

- [ ] **13. A swing before the stop's first fix is dropped.**
  `StrokeFinder.swift:126` requires `swing.timestamp >= stop.start`, even though `contains` already allows 2 s of slack.
  *Fix:* review. Allow the slack before the start too.

- [ ] **14. A stop more than 60 m from the centerline is dropped unless it is a tee shot.**
  `StrokeFinder.swift:133`. A shot from a neighboring fairway or from deep trouble is lost.
  *Fix:* review.

- [ ] **15. A wrong hole timeline puts the swing on another hole.**
  `StrokeFinder.swift:99-101`.
  *Result (no change):* this is how ending from the phone works. Swings are only lost if End is tapped before the last shot.

- [x] **16. Same-stop and closer-to-green rules hide swings.**
  Only the last swing in a stop counts. A new stop counts only if it is at least 3 m closer to the green (`StrokeFinder.swift:136-157`). For example, a shot played sideways out of trouble would be hidden.
  *Fix (done):* replaced by the full-swing rules in `plans/2026-10-04-full-swing-strokes.md`. The strongest swing at a spot is the shot, and there is no closer-to-green rule.

- [x] **17. A cap of 10 suggestions per hole.**
  `StrokeFinder.swift:41, 173`. Stops near the green fill the list before later swings.
  *Fix (done):* full swings are never cut; the cap applies to putt and chip suggestions (`plans/2026-10-04-full-swing-strokes.md`).

- [ ] **18. Suggestions only show in edit mode.**
  `RoundMapView.swift:846`.
  *Result (no change):* this is how ending from the phone works. Swings are only lost if End is tapped before the last shot. This is a UI choice, not a bug.

- [ ] **19. Reading times may be converted wrongly.**
  `SwingDetector.swift:36` builds the boot date from `systemUptime`. If the sensor timestamps use a different clock, swings would fall outside their stops.
  *Fix:* check against Apple's documentation. Compare the newest reading's time with `Date()` once per start.
