# Putt Lab in rounds

Putt Lab (`2026-10-06-putt-capture.md`) runs during a round too, recording a segment per green visit, and the Mac pulls captures straight from the watch. The Broadlands round of 2026-10-12 found 176 contacts for 19 putts; the raw signal around each, with marks, is what a better detector needs.

Nothing off the green changes. The swing detector, the contact detector, its zone and its thresholds are untouched. The phone's only change is the setting in section 2.

## 1. Segments

A capture becomes a folder of segments. A segment is what a capture is today: the six files, times since the segment's start.

```
Documents/putt-captures/<captureID>/
  001-hole1/  accel.bin motion.bin audio.wav contacts.csv marks.csv meta.json
  002-hole2/  …
```

| Where | Segments |
|---|---|
| Outside a round | One, `001-hole0`, Start Capture to Stop, as today |
| In a round | One per green visit: starts when `ContactMonitor` turns its sensors on, ends when it turns them off. Nothing is written between greens. The capture runs from the round's start to its end, or to Stop on the page |

In a round the segment writes the contacts `ContactMonitor` finds instead of running its own `ContactRunner`, so one detector runs.

`meta.json` goes to `version` 2. New fields, all optional, so version 1 decodes and `analyze-capture.py` reads a segment unchanged:

| Field | Meaning |
|---|---|
| `captureID` | The capture folder's UUID. `id` stays the segment's own |
| `roundID` | Absent outside a round |
| `hole` | The display hole when the segment started, 1-based; 0 outside a round |
| `segment` | From 1 |
| `endReason` | `stopped`, `leftGreen`, `holeAdvanced`, `workoutStopped`, `roundEnded`, `appTerminated` |

`startBattery` and `endBattery` are filled in per segment.

A segment left open by a kill is finished on the next launch: `endReason: appTerminated`, counts from the file sizes.

A segment does not start under `minFreeSpace = 2 GB` free; the page says so.

Expected size: 7.5 MB a minute recording, 500 to 620 MB a round at 67 to 83 minutes on greens. Writing at that rate during a round is the one unmeasured battery cost; the per-segment battery levels measure it on the first round.

## 2. Putt Lab during a round

Phone Settings gets **Putt Lab During Rounds**, `SettingsKey.puttLabInRounds`, on by default. It travels in `StartRound.puttLab` (decoded as true when missing) and the watch keeps the last value in `UserDefaults`, like `debugLogging`, so a round resumed after a relaunch keeps it.

With it on, the round records a capture without a tap: the capture folder is made when the round starts, and segments follow the greens. The Putt Lab page is the round's third page, after the end-round page, and the watch brings it to the front when a segment starts, so the mark buttons are under the finger on the green, and goes back to the info page when the segment ends. Stop on the page ends the capture for the rest of the round.

| State in a round | Shows |
|---|---|
| Between greens | The hole, "Waiting for a green", Stop |
| On a green | Recording, unchanged |
| Stopped, or the setting off | "Putt Lab is off for this round" and where to turn it on |

Ending the round ends the capture.

## 3. No more sending to the phone

`PuttCaptureUploader` is removed, and with it the phone's `PuttCaptureStore`, `PuttCapturesView` and the Settings link.

## 4. Pull and delete

`pull-putt-captures.sh [--watch <UDID>] [--to <folder>]`:

1. Lists `Documents/putt-captures` on the watch with `devicectl device info files --json-output`.
2. Copies every file not already in `Data/putt-captures/<captureID>/<segment>/` with the same size, with `devicectl device copy from`.
3. Checks each segment: `accel.bin` is `accelCount × 20` bytes, `motion.bin` is `motionCount × 60`, the WAV's frames are `audioFrames`.
4. Prints each capture's segments: hole, length, marks, contacts, battery drop.

`devicectl` cannot delete, so a **Captures** page on the watch lists each capture with its date, round or "Putt Lab", segment count and size, with swipe to delete.

Found on the way: the writers opened each CSV at offset 0, so a segment's first contact or mark line overwrote the header. They now append after it.

## 5. Code

| Where | Change |
|---|---|
| `Shared/Models/PuttCapture.swift` | Version 2 fields on `Meta`; segment folder names |
| `Shared/Models/SyncMessage.swift` | `StartRound.puttLab` |
| `SpotGolf/Models/SettingsKey.swift`, `Views/SettingsView.swift`, `Sync/PhoneSync.swift` | The toggle, sent with `StartRound` |
| `SpotGolfWatch/PuttLab/CaptureWriter.swift` (new) | The file writing pulled out of `PuttCaptureRecorder`: one segment's folder, files, queue and `meta.json` |
| `SpotGolfWatch/PuttLab/PuttCaptureRecorder.swift` | A capture of segments. In a round: started by the round, a segment per `ContactMonitor` session, contacts from the monitor, no runner. Free space, kill recovery |
| `SpotGolfWatch/Contacts/ContactMonitor.swift` | `onSession: (SessionChange) -> Void` with the hole and the reason |
| `SpotGolfWatch/Views/PuttLabView.swift` | The in-round states, the Captures link |
| `SpotGolfWatch/Views/CapturesView.swift` (new) | The list with sizes and delete |
| `SpotGolfWatch/Views/WatchRoundView.swift` | Putt Lab as the round's third page, brought to the front when a segment starts and left when it ends |
| `SpotGolfWatch/Sync/WatchSync.swift` | Keeps `puttLab` from `StartRound`; the round's start and end start and end the capture |
| `PuttCaptureUploader.swift`, `PuttCaptureStore.swift`, `PuttCapturesView.swift` | Removed, with their wiring in `WatchServices`, `PhoneServices` and `SettingsView` |
| `pull-putt-captures.sh` (new) | Section 4 |

## Checks

1. Unit tests: `CaptureWriter` writes a segment with the right sizes and finishes `meta.json`; `Meta` version 2 round-trips and version 1 decodes; `StartRound` decodes without `puttLab` as true.
2. `PuttCaptureRecorder` with the fake sensors: outside a round one segment as before; in a round the capture starts with the round, a segment per session with the hole and reason, nothing written between greens, no segment under `minFreeSpace`, a kill-and-relaunch closes the open segment, Stop and the round's end stop the capture, nothing recorded with the setting off.
3. Simulator round on the session's clones: the page comes to the front on entering the green and leaves on exit; segment folders appear and disappear with the green zone; the stream is exactly what it was.
4. A real round: `pull-putt-captures.sh` brings every segment over and the checks pass; `analyze-capture.py` reads a segment; the battery drop per segment.

## Steps

1. `CaptureWriter` out of `PuttCaptureRecorder`; `Meta` version 2; tests.
2. Segments in a round; tests.
3. The phone setting and `StartRound.puttLab`; the page in the round and its switching; the Captures page.
4. Remove the uploader and the phone's capture code.
5. `pull-putt-captures.sh`, run against the watch with a short capture.
