# Developer Mode

Putt Lab During Rounds (`SettingsKey.puttLabInRounds`) is on by default and shown to every player today. It records whole greens (about 500 MB a round), brings the Putt Lab page to the front, and only a developer with Xcode can get the data off the watch. Players should not see it.

Developer Mode replaces Putt Lab and Putt Lab During Rounds. It is one switch, hidden until unlocked, for committers on the SpotGolf open-source project, whose phone and watch are set up as development devices. With it on, the watch records every round as Putt Lab During Rounds does today. Round data leaves the devices only through `Scripts/export-round.py`. Nothing is uploaded.

Asking players to share putting data is a separate feature, Putt Data Sharing (`2026-10-27-putt-data-sharing.md`).

## 1. Turning it on

| Step | Behavior |
|---|---|
| Tap **Version** in phone Settings 7 times | The **Developer Mode** switch shows in a **Developer** section, turned on. A short message says "Developer Mode on" |
| Switch turned off | Recording stops from the next round (or at once in a round, as the setting does today), and the section hides again |

- The tap count resets after 2 s without a tap.
- Stored as `SettingsKey.developerMode`, off by default, in the phone's `UserDefaults`. It is not saved to iCloud (`SyncedSettings`), so it stays on the one phone.
- Footer text: "The watch records wrist motion and sound on each green, for working out how to detect putts. The recordings stay on the watch. Get them with Scripts/export-round.py."

## 2. Renames

Every "Putt Lab" name becomes "Developer Mode": settings, messages, types, files, folders, user-facing text, log category, comments and scripts. Names about captures (`PuttCapture`, `Documents/putt-captures`, `CaptureWriter`, `CaptureAudioWriter`) describe the data, not Putt Lab, and stay. Plans written before this one are history and are not edited.

### 2.1 Settings and messages

| Today | Becomes |
|---|---|
| `SettingsKey.puttLabInRounds` (default true) | `SettingsKey.developerMode` (default false) |
| Settings section "Putt Lab", toggle "Putt Lab During Rounds" (`PuttLabInRounds`) | Hidden section "Developer", toggle "Developer Mode" (`DeveloperMode`) |
| `PhoneSync.puttLab` | `PhoneSync.developerMode` |
| `StartRound.puttLab`, decoded as true when missing | `StartRound.developerMode`, decoded as **false** when missing |
| `RoundSettingsMessage.puttLab` | `RoundSettingsMessage.developerMode` |
| `WatchSync.puttLabKey` = `"puttLabInRounds"`, `WatchSync.puttLabInRounds` (true until told) | `WatchSync.developerModeKey` = `"developerMode"`, `WatchSync.developerMode` (**false** until told) |
| `WatchServices.puttLabInRound` | `WatchServices.developerModeInRound` |

### 2.2 Code and files

| Today | Becomes |
|---|---|
| `SpotGolfWatch/PuttLab/` | `SpotGolfWatch/DeveloperMode/` |
| `PuttLabView` | `DeveloperModeView` |
| `WatchRoundView.Page.puttLab` | `WatchRoundView.Page.developerMode` |
| `LogCategory("puttLab")`, `Log.puttLab` | `LogCategory("developerMode")`, `Log.developerMode` |
| Test names with `PuttLab` (`PuttLabRanInRoundsHasItOn`, `PuttLabSettingReachesTheWatch`, and others) | The same with `DeveloperMode` |
| "Putt Lab" in comments in Swift and in `Scripts/` | "Developer Mode" |

### 2.3 Text players or developers see

| Today | Becomes |
|---|---|
| Watch page title "Putt Lab" | "Developer Mode" |
| "Putt Lab is off for this round. Turn on Putt Lab During Rounds in Settings on your iPhone before the next round." | "Recording is off for this round. It starts again next round while Developer Mode is on." |
| Phone "Putt Lab", "Putt Lab During Rounds" | "Developer", "Developer Mode" |
| Microphone permission (`NSMicrophoneUsageDescription` in `project.yml`): "SpotGolf records sound in Putt Lab to learn what a putt sounds like." | "SpotGolf listens for the sound of the ball being hit to find your putts." The mic is used by every player's putt detection, so it does not name Developer Mode |

Both `Localizable.xcstrings` catalogs get the new keys and lose the old ones, changed by script, not by `xcstringstool sync`, which rewrites the whole catalog.

The message fields change name, so a phone and watch on different builds disagree. The app is not in production and no players are on older builds, so no compatibility code is kept. Old `puttLabInRounds` values in `UserDefaults` are ignored.

## 3. Outside a round

Developer Mode does nothing outside a round. Everything Putt Lab does outside a round today is removed; Putt Data Sharing's drills replace it.

| Removed | Where today |
|---|---|
| The Putt Lab page in the no-round `TabView` | `WatchRoundView` |
| Start Capture, the capture's own workout and its own `ContactRunner` | `PuttLabView` (`idle`), `PuttCaptureRecorder` (`State.starting`, the workout listener, `runner`) |
| The single-segment capture, `001-hole0` | `PuttCaptureRecorder`, `CaptureWriter` |
| The mark buttons outside a round | `PuttLabView` |
| The Captures screen: list and delete | `CapturesView`, the Captures button in `PuttLabView` |
| `Scripts/pull-putt-captures.sh` | Data leaves only through `Scripts/export-round.py` (section 5) |

- The recorder keeps only the in-round path: segments started and ended by `ContactMonitor`, with the contacts the round's detector finds.
- The watch needs Developer Mode only in a round, so it still learns it from `StartRound` and `RoundSettingsMessage`. No message is added outside rounds.
- Captures are deleted by the app, never by hand (section 3.1).

### 3.1 Keeping captures

Every capture belongs to a round (`Meta.roundID`). The watch keeps captures for the last 5 rounds only.

| When | The watch deletes |
|---|---|
| A round starts (`StartRound` accepted), before its capture folder is made | Every capture with no `roundID` (made outside a round before this change), and every capture not from the 4 most recent other rounds, so with the new round 5 are kept. Rounds are ordered by the capture's `startDate` |
| A round is deleted on the phone | That round's capture |

A round is deleted on the phone in three ways, and each sends the watch a new message, `SyncMessage.roundDeleted(RoundDeleted { roundID })`:

| Path | Code |
|---|---|
| Swipe to delete in the round list | `RoundListView` → `RoundStore.deleteRound` |
| The round is canceled | `PhoneSync` cancel path, which already sends `CancelRound`; the watch deletes the capture on `CancelRound` too, so no second message |
| Deleted on another device, through iCloud | `CloudSync.deletedRound` |

- The message is sent with `sync.queue`, so a watch that is away gets it later.
- The watch deleting its own copy of a finished round (`WatchSync.pruneFinishedRounds`, a day after the end) does **not** delete the capture: the capture must outlive it for `export-round.py`.
- A message for a round with no capture does nothing.

## 4. In a round

With Developer Mode on, the round records one segment per green visit, every stream, as in `2026-10-12-putt-lab-in-rounds.md`.

| | Today | With Developer Mode |
|---|---|---|
| A segment starts on a green | `WatchRoundView` switches to the Putt Lab page | **No switch.** The watch stays on the page the player is on. The Developer Mode page is reached by swiping, as any other page |
| A segment ends | Switches back to the info page | No switch |
| Setting off | Putt Lab page shows "Putt Lab is off for this round" | The Developer Mode page is left out of the round's pages, so a player never sees it |
| Stop tapped on the page | Page shows the off text | Page stays and shows the off text (2.3) |

The `onChange(of: services.puttCapture.state)` in `WatchRoundView` that switches pages is removed. The screen no longer wakes to the page on each green, which also saves battery.

## 5. Getting the data

`Scripts/export-round.py` already exports a round's capture with the phone's store into one folder for `replay-round.py`. Its header comment and its README section say that a round has a capture only when Developer Mode was on.

## 6. Versioning

MINOR: a `feat`, and the renamed message fields are a breaking change, which is MINOR before 1.0.0 (see the version table in `CLAUDE.md`).

## 7. Testing

| Area | Test |
|---|---|
| Hidden switch | UI test: 7 taps on Version show the Developer section with the switch on; 6 taps, or a 2 s pause, do not |
| Turning off | UI test: the section hides; the next round's `StartRound.developerMode` is false |
| Messages | `SyncCodecTests`: `StartRound` without `developerMode` decodes as false |
| Sync | `SyncFlowTests`: the existing Putt Lab tests renamed, with the default now false |
| Watch pages | UI test on the session's clone pair: no Developer Mode page outside a round, with Developer Mode on or off; in a round, the page shows only with Developer Mode on, and a segment starting leaves the current page in front |
| Keeping captures | Unit: with captures from 6 rounds and one with no `roundID`, a round start leaves the 4 newest plus the new one; `roundDeleted` and `CancelRound` delete that round's capture; `pruneFinishedRounds` does not |
| Round deleted | `SyncFlowTests`: deleting a round in the store, and through `CloudSync.deletedRound`, queues `roundDeleted`; `SyncCodecTests`: `RoundDeleted` round trip |
| Removed code | Tests of the outside-round capture and of `CapturesView` are deleted with them |
| Renames | `grep -ri "putt ?lab"` over the code, `Scripts/`, `project.yml` and the string catalogs finds nothing |
