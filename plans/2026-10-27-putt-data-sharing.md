# Putt Data Sharing

Every putt capture so far is one player with one putter. The gate's limits (`StrokeGate`) and the click and burst limits (`ContactDetector`) may differ for other players and other equipment (see `2026-10-16-bear-dance-putt-analysis.md`, "One player" and "Trail wrist").

This feature asks any player to do a set of putting drills on a practice green. The watch records every stream for the whole session, packs it and sends it to the phone, and the phone uploads it to CloudKit. The developer pulls it to the Mac with a script into the layout `analyze-capture.py` already reads.

Recording whole rounds is a separate feature, Developer Mode (`2026-10-27-developer-mode.md`), which replaces Putt Lab. The drills run whether Developer Mode is on or off.

## Goals

| Goal | How |
|---|---|
| Labeled data from many players and putters | Guided drills: the app knows what each task is |
| No developer tools for the player | Everything starts from the phone and watch apps; upload is automatic |
| Clear consent | Consent screen before anything is recorded; shared data can be deleted |

Out of scope: recording during rounds, per-player calibration, changing the detector's limits.

## 1. Phone

### 1.1 Entry point

A new top-level screen, **Putt Data Sharing**, reached from a toolbar button on `RoundListView`.

| Section | Contents |
|---|---|
| About | What is recorded (wrist motion, sound, and one location at the start), why, who sees it |
| What you need | "You need a putter, 5 balls and an outdoor practice green. Each drill is 5 repeats the same task (i.e. "Hit a 3 foot putt"). After you complete the 5 tasks, the drill ends. Between drills you collect your balls and set up for the next drill." |
| How it works | "Start on your watch. Read the instructions for each task on your watch, do the task, then tap Done." The phone does not list the drills or tasks, so the player never takes the phone out of a pocket during a session |
| Consent | "I agree" button. Nothing below is enabled until it is accepted. Consent is stored with its version; a new consent version asks again |
| My setup | The equipment profile (1.2) |
| Upload on cellular | Switch, off by default |
| Sessions | Each session: date, drills finished, size, state (on watch, on phone, uploading, uploaded, failed). Swipe to delete. **Delete all my data** button |

### 1.2 Equipment profile

Asked once on the phone (typing on the watch is hard), sent with every session, editable any time.

| Field | Choices |
|---|---|
| Hand | Right, left |
| Putter head | Blade, mallet |
| Putter face | Insert, milled or metal |
| Putter length | Standard, arm-lock, long or broomstick |
| Grip | Standard, cross-handed (lead hand low), claw, other |
| Ball | Soft (urethane cover), firm (two-piece), don't know |
| Handicap | Under 10, 10 to 20, over 20, no handicap |

The wrist and the crown side are read on the watch, as Developer Mode does in rounds (`wristLocation`, `crownOrientation`).

### 1.3 Settings sync

`consentVersion` and the equipment profile reach the watch outside a round, which no message does today (`RoundSettingsMessage` carries a round ID). They are not saved to iCloud (`SyncedSettings`).

| | |
|---|---|
| Message | `PhoneSettingsMessage { consentVersion: Int?, sharerID: UUID?, equipment: Equipment? }`, a new `SyncMessage.phoneSettings` case. All nil before consent |
| Sent | Queued (`transferUserInfo`), so a watch that is away gets it: when consent, the profile or the sharer ID changes, and once per phone launch when the watch is first seen |
| Kept | On the watch in `UserDefaults` (`WatchSync.phoneSettingsKey`) |

The watch shows the drills only after consent has arrived.

## 2. Watch

### 2.1 Entry point

With no round, `WatchRoundView` shows a page `TabView` again: the no-round page, then a **Putting Drills** page. With no consent it says "Open Putt Data Sharing on your iPhone to start". The drills cannot start during a round.

### 2.2 Flow

A session is a list of drills (2.3). A drill is 5 tasks with the same setup. A task is one thing done once, such as one putt.

```
Putting Drills page: "You need a putter, 5 balls and a practice green."
   │ Start
   ▼
Starts its own workout, the sensors and a ContactRunner
   │
   ▼
Paused screen: "Next: 3 foot putts. Put 5 balls 3 feet from a hole." ── Ready ──┐
   ▲                                                                            │
   │                                                                            ▼
   │                                    Task screen: "Hit a 3 foot putt, then tap Done."
   │                                          │ Done (the next task shows at once)
   │                                          ▼
   │                                    5 tasks done?
   │                                     │ no: next task screen
   └──── yes, drills left: "Collect your balls. Next: 10 foot putts. …" ── Ready
                                         │ yes, last drill
                                         ▼
                              Finished: "Sent to your iPhone" ── packs and transfers (section 3)
```

| Screen | Shows | Buttons |
|---|---|---|
| Paused | What to do now ("Collect your balls", or nothing before the first drill), the next drill and how to set it up. For drills with no ball: "No balls needed" | **Ready** |
| Task | One task, worded for a single try: "Hit a 3 foot putt, then tap Done." Drill and task number in small fixed text, such as "Drill 1 · 2 of 5" | **Done** |
| Second page (swipe) | | **Skip drill**, **Stop** |

- One task at a time, so no one thinks they must do all 5 before tapping Done.
- Task and paused screens never play a haptic, since haptics have caused false contacts (`2026-10-16-bear-dance-putt-analysis.md`, haptics).
- Done shows "Saved" over the whole page for 2 s, its dots filling in from one to three, so the player knows the tap counted. The next task shows when it goes.
- The text is large and in the primary color (white on the watch's dark background), not the dim secondary color, so it reads at arm's length.
- Each Done tap is the task's end, and the start of the next task. Each Ready tap starts the drill's first task. Both are written to `events.csv` and `drill.json`.
- Reaching for Done is a wrist raise. That is wanted: it gives labeled false contacts.
- Recording runs through the paused screens too. Collecting balls is labeled as a pause, which gives more false contacts with a known label.
- **Skip drill** goes to the paused screen for the drill after it. **Stop** ends the session; a session stopped early is still sent with the drills finished.
- Developer Mode removes Putt Lab's outside-round capture (`2026-10-27-developer-mode.md`, section 3). The drill recorder does the same job: its own workout and `ContactRunner`, one segment written with `CaptureWriter`. The removed code in git history is the starting point.
- Every stream is recorded for the whole session: accelerometer, device motion, microphone, contacts, candidates, events. No GPS track. One session is one segment in today's layout (`PuttCapture`), with two new files (3.1).

### 2.4 Starting location

One location is kept per session, to check that it was recorded on an outdoor putting green and that the data is good. The session never waits for it or needs it, so it also works on an indoor green.

| | |
|---|---|
| When | Location updates start when Start is tapped and stop once a fix is kept, or after 60 s |
| Kept | The first fix with horizontal accuracy 30 m or better. With none, the best fix seen. With no fix at all, none |
| Stored | In `sharing.json` as `location`: latitude and longitude rounded to 4 decimal places (about 11 m), horizontal accuracy, and seconds from the session's start. Without a fix, `location` is absent and `locationStatus` says why: `denied`, `noFix` |
| Permission | The location permission the app already has for rounds. No new prompt; when it is denied, the session runs without a location |
| Shown | Nowhere on the watch. The phone's Sessions list shows "Location: yes" or "Location: no" |

Rounding to 4 decimal places is enough to see the green on a satellite map, and keeps the exact spot out of the data.

### 2.3 Drills

Each drill is 5 tasks. The order keeps ball handling low: the tap-ins leave the balls in the cup for the drill after them, and the drills with no ball need no collecting.

| # | Paused screen: setup | Task screen | Expected label | Tests |
|---|---|---|---|---|
| 1 | Put 5 balls 3 feet from a hole | Hit a 3 foot putt, then tap Done. | putt | `minBackswing`, short strokes |
| 2 | Put 5 balls 10 feet from a hole | Take one practice stroke, hit a 10 foot putt, then tap Done. | practice, then putt | Practice strokes against putts |
| 3 | Put 5 balls 30 feet from a hole | Hit a 30 foot putt, then tap Done. | putt | `maxTilt`, `maxBackswing`, `topSearch` on long strokes |
| 4 | Put 5 balls 1 foot from a hole | Tap in a 1 foot putt, then tap Done. | putt | The score floor |
| 5 | Leave the balls in the cup | Pick a ball out of the cup, then tap Done. | none | Wrist raises |
| 6 | No balls needed | Take a practice stroke with the putter above the grass, then tap Done. | practice | None should pass |
| 7 | No balls needed | Take a practice stroke that brushes the grass, then tap Done. | practice, ground | None should pass; ground contact makes a burst |
| 8 | Put a ball 2 feet from you | Pull the ball toward you with the putter head, then tap Done. | none | Knocks |

40 tasks. At 10 to 20 s a task plus 1 to 2 minutes of collecting between drills, a session is about 20 minutes.

Not in the drills:

- Chips: a separate feature.
- The other wrist: the watch cannot tell which wrist a player putts with, and players don't move the watch reliably. Wrist and crown side are recorded as the watch reports them (`wristLocation`, `crownOrientation`), with the player's hand from the equipment profile (1.2).
- Looking at the watch: every Done tap is one.
- Bouncing the ball on the putter: most players can't.

## 3. Data format and transfer

### 3.1 New files

| File | Contents |
|---|---|
| `drill.json` | Drill list version; each drill: number, its Ready time, skipped; each task: drill, task number, prompt key, start (shown) and Done times |
| `sharing.json` | Session ID, app version, watch model, watchOS version, consent version, sharer ID, equipment profile, starting location (2.4) |

The sharer ID is a random UUID made at consent, kept in the phone's settings. It is not the iCloud account. **Delete all my data** makes a new one.

### 3.2 Packing

A session records about 7.4 MB a minute, about 150 MB for 20 minutes.

Recording is the same as in a Developer Mode round: `CaptureWriter` and `CaptureAudioWriter` write `audio.wav`, 16-bit PCM, so drills and rounds give the same training data. The audio is made smaller only for the trip, after the session ends:

```
Session ends ──► audio.wav ──► audio.caf (ALAC) ──► decode, compare with audio.wav
                                                         │ same samples     │ any difference or failure
                                                         ▼                  ▼
                                                   archive audio.caf   archive audio.wav
                                                         │
                                                         ▼
                                   folder ──► one Apple Archive (.aar), LZFSE ──► transfer (3.3)
```

| Data | In the archive |
|---|---|
| Audio | `audio.caf`, Apple Lossless (ALAC), 16-bit, same sample rate, converted with `AVAudioFile`. Lossless, so the samples are exactly those in `audio.wav`; lossy formats are not allowed, since they may blur the 1 ms click peak. When the conversion fails or the decoded samples differ, `audio.wav` goes in instead |
| Everything else | As recorded |
| The folder | One Apple Archive (`.aar`), LZFSE compressed |

- Converting runs on a utility queue once the session is finished, never while recording.
- `audio.wav` is deleted only when the archive is made. The session folder and archive are deleted after the transfer (3.3).
- `sharing.json` records which audio file the archive holds.

Measured on a Series 10 (Watch8,3), 2026-10-27: a 7.3 minute session of all 8 drills recorded 54 MB and packed to 15.9 MB (29%). A 20 minute session packs to about 45 MB.

### 3.3 Watch to phone

```
Watch: session ends ──► pack ──► WCSession.transferFile(archive, metadata: session ID, size)
                                        │
                                        ▼ (background, retried by the system)
Phone: session(_:didReceive:) ──► Application Support/putt-sharing/pending/ ──► upload queue
                                        │
Watch: didFinish fileTransfer, no error ──► delete the archive and the session folder
```

- The watch keeps at most 500 MB of unsent archives. Above that it does not start a session, and the page says so.
- The phone's Sessions list shows archives the watch reported but the phone has not yet received as "on watch".

### 3.4 Phone to CloudKit

The public database of `iCloud.golf.spot.SpotGolf`, which `CloudKitPinSharing` already uses. The private database cannot be read by the developer.

#### Why CloudKit, not S3

| | CloudKit public database | S3 |
|---|---|---|
| Backend to run | None | A signing service (for example a Lambda) to hand out upload URLs |
| Who may upload | Signed-in iCloud users only, enforced by CloudKit | Needs its own check (App Attest or similar), or anyone with the URL can fill the bucket |
| Cost | No charge within the app's quota | Small, but a bill and an AWS account to keep |
| Per-file size | Up to 50 GB per `CKAsset` (Apple engineer, developer forums); a session is about 45 MB | No practical limit |
| Storage | 10 GB of assets to start, growing with the app's active users | No practical limit |
| Developer download | Web Services with a server-to-server key (public database only) | Any S3 client |

The one tight limit is the starting 10 GB, about 220 sessions. The design keeps CloudKit as a queue rather than an archive: the Mac script deletes each session from CloudKit once it is pulled and checked (section 4), so storage holds only sessions not yet pulled. The archive lives in `Data/shared-putts/` on the developer's Mac. With the developer pulling each week, 10 GB is far more than needed.

Over the limit, saves fail with `CKError.quotaExceeded`: sessions stay queued on the phone and upload once the developer has pulled, and the Sessions list shows "Waiting to upload".

Record type `PuttSession`:

| Field | Type |
|---|---|
| `sessionID` | String |
| `sharerID` | String |
| `appVersion` | String |
| `createdDate` | Date |
| `size` | Int64 |
| `archive` | Asset |

| Security role | Rights |
|---|---|
| World | None |
| Authenticated | Create |
| Creator | Read, write |

- Upload with `CKModifyRecordsOperation`, `allowsCellularAccess` from the setting, retried on failure with backoff. The local archive is deleted once the save succeeds.
- Writing to the public database needs an iCloud account on the phone. Without one the screen says so and sessions stay queued.
- `CKError.quotaExceeded` and `limitExceeded` are retried hourly, not with backoff, since they clear only when the developer pulls.
- Delete one session: the phone deletes its record by `sessionID` (the creator role allows it), and also saves a `PuttDeletion` record, since the session may already be pulled and gone from CloudKit.
- **Delete all my data:** saves a `PuttDeletion` record for the sharer ID, deletes every `PuttSession` record still there with that sharer ID, then local files, then makes a new sharer ID.

Record type `PuttDeletion`, same security roles:

| Field | Type |
|---|---|
| `sharerID` | String |
| `sessionID` | String, absent for "all my data" |
| `createdDate` | Date |

- A `PuttSession` record's name is its session ID, so the phone deletes it without a query. Deleting a session that was uploading also sends a deletion, since its upload may still finish.
- **Spike 2** checks, on the CloudKit development environment, the things the design depends on: a phone saves an 80 MB `CKAsset`; the server-to-server key can query, download and delete records the phone created; the key can read `PuttDeletion` records; and `recordName` is marked queryable for both record types, which a query with no filter usually needs.

## 4. Mac

`Scripts/pull-shared-putts.py`:

- Queries the public database with CloudKit Web Services and a server-to-server key (these keys work only on the public database). The key file stays outside the repository, its path given by an environment variable.
- Downloads sessions not already pulled, unpacks them into `Data/shared-putts/<sharerID>/<sessionID>/`, converts `audio.caf` back to `audio.wav` (the same samples, so the folder matches a Developer Mode segment), and checks file sizes against `meta.json`, as the removed `pull-putt-captures.sh` did.
- Deletes each session's `PuttSession` record from CloudKit once its folder passes the checks, so CloudKit holds only sessions not yet pulled (3.4). `--keep` skips this.
- Reads `PuttDeletion` records and deletes the matching folders on the Mac (one session, or every session of the sharer ID), then deletes the `PuttDeletion` record. This runs before downloading, so a deleted session is never pulled again.
- Prints a summary: sharers, sessions, putter and grip counts, drills finished.

`analyze-capture.py` reads a session unchanged. Matching tasks to contacts uses the task times in `drill.json`.

## 5. Privacy

| Item | Detail |
|---|---|
| Consent | Shown before any recording; names the microphone and that speech nearby may be recorded |
| App Store privacy labels | Audio data, precise location, other diagnostic data. Not linked to identity; not used for tracking |
| Privacy policy | A section on shared putt data: what, why, how long, how to delete |
| Location | One location per session, rounded to about 11 m, kept to check the session was on a putting green (2.4). Apple counts 3 or more decimal places as precise location, so the App Store privacy label is precise location, not linked to identity |
| Deleting | Per session and all at once, on the phone. Reaches data already pulled to the developer's Mac through `PuttDeletion` records, applied by the next pull (3.4, 4) |
| Microphone | Already asked by the app; nothing new |

## 6. Versioning

`feat`: MINOR. New `SyncMessage` cases for the phone settings and the transfer report, with optional fields, so older builds ignore them. No saved-round change.

## 7. Testing

| Area | Test |
|---|---|
| Packing | Round trip: pack, unpack, compare files; WAV to ALAC and back is bit exact; a failed or different conversion archives `audio.wav` |
| Drill flow | Unit: drill and task state machine (paused, task, next task on Done, paused between drills, finished), skip drill, stop early, `drill.json`; UI test on the session's clone pair |
| Transfer | On the session's clone pair: `transferFile` arrives and the watch deletes after success |
| Upload | Manual, against the CloudKit development environment: upload, pull and delete from CloudKit, delete one and delete all before and after a pull, `quotaExceeded` keeps the session queued |
| Starting location | Unit: a fix at 30 m or better is kept at once; with only worse fixes, the best is kept at 60 s; with none, `noFix`; with permission denied, `denied`; rounding to 4 decimal places. The session starts and runs in every case |
| Real use | One session on an outdoor practice green and one indoors by the developer, pulled and run through `analyze-capture.py` |

## 8. Spikes, before building

1. Converting a session's WAV to ALAC on the watch. Done 2026-10-27 on a real watch: it works, the pulled WAV matched `audioFrames` exactly, and the session packed to 29% of its recorded size.
2. Done 2026-10-27: the first upload created `PuttSession` in the development schema, and the server-to-server key queried, downloaded and deleted the player's records under the creator-only roles, including a `PuttDeletion` the phone saved, which the pull applied to the Mac. CloudKit on the development environment: an 80 MB asset saves from the phone, and the server-to-server key can query, download and delete the phone's records and read `PuttDeletion` (3.4). The CloudKit choice is made; this checks only that the pieces work as documented.
