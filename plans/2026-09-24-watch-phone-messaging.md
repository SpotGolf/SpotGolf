# Watch ↔ Phone Messaging

## Summary

Replace the current `SyncService` messaging with one messaging service. Each message type is a model object. Each type gets the delivery method its needs call for. Nothing uses one blanket rule.

The watch records all GPS and swings. The phone owns the round: course, marks, guesses, and settings. The watch shows the round and records data. It edits nothing except the current hole.

## Decisions

| Topic | Decision |
|---|---|
| Hole timing | The round stores a **hole timeline**. The hole for any timestamp comes from the timeline, so a late hole change never has to rewrite data |
| Hole order | Golf is linear. The hole in the timeline only goes up. "Play this hole" is offered only for holes after the current one. Skipped holes are filled in from the GPS track |
| Hole confirmation | Each entry stores how it was made (`source`). Whether it is confirmed is worked out from marks, not stored. The phone moves entries that the marks show are wrong |
| Shotgun start | Not supported yet. Rounds start on the first hole in playing order |
| Start round | Phone → watch only. Handshake. The round is Active only after the watch acks it |
| Start Round button | Enabled when a watch is paired and the watch app is installed. It does not need the watch to be reachable |
| Watch app not running | The phone launches it with `HKHealthStore.startWatchApp(with:)` |
| Course transfer | One `sendMessage` when it fits, chunks when it doesn't. No `transferFile` (it does not work between simulators and is slow) |
| End round | Either side can start it. The phone stays **Ending** until it has every GPS record up to the watch's `lastSeq` |
| End round, watch unreachable | The phone stays Ending and shows a **Force end** button |
| GPS | Ordered stream with an index. The phone replies `have`. The watch sends on **every fix**, with one batch in flight |
| Swing detection | `CMBatchedSensorManager` on the watch |
| Swing events | Timestamp only, sent in the GPS stream. The phone works out the location and hole, and makes the guess |
| Stationary guesses | Removed from the watch. The phone's `MarkSuggester` already finds dwell spots from the GPS track |
| Marks | Phone → watch. Full snapshot with a `marksVersion` counter |

## Messages

| Message | Direction | Delivery class | Must arrive | Order matters | Safe if received twice | Sender waits |
|---|---|---|---|---|---|---|
| `StartRound` | P→W | Handshake | Yes | – | Yes (round ID) | Yes, for `StartRoundAck` |
| `StartRoundAck` | W→P | Reply to `StartRound` | – | – | Yes | – |
| `CancelRound` | P→W | Queued | Yes | – | Yes | No |
| `EndRequest` | P→W | Handshake | Yes | – | Yes | Yes, for `EndAck` |
| `EndRound` | W→P | Handshake | Yes | – | Yes | Yes, for `EndAck` |
| `EndAck` | Both | Reply | – | – | Yes | – |
| `StreamBatch` (GPS fixes + swings) | W→P | Stream | Eventually | Yes | Yes (index) | One batch in flight |
| `StreamAck` (`have`) | P→W | Reply to `StreamBatch`, or sent alone on phone launch | – | – | Yes | – |
| `HoleTimeline` | Both | Snapshot | Yes | No (merged) | Yes | No |
| `MarksSnapshot` | P→W | Snapshot | Latest only | Handled by version | Yes | No |

Messages that are removed: `addMark`, `setMarkType`, `addGuess`, `removeGuess`, `updateSettings`, `setHole`, and the `track` file transfer. The only setting is `stationaryThreshold`, and only the watch's stationary detection used it. Once that moves to the phone, the watch needs no settings.

## Transport

| API | Used for | Why |
|---|---|---|
| `sendMessage` with `replyHandler` | Every message, when the other side is reachable | Fast. The reply or the error handler tells the sender what happened. Every call uses a reply handler, so no failure goes unseen |
| `transferUserInfo` | Backup copy of `EndRequest`, `EndRound`, `CancelRound` | Always arrives, in order, even after the sender quits. Duplicates are safe for these messages |
| `updateApplicationContext` | Backup copy of `HoleTimeline` and `MarksSnapshot` | The latest value always arrives. Each call replaces the whole context, so the service always sends the full current context |
| `transferFile` | Not used | |

### Wire format

Every message is one entry: `["m": Data]`. The data is the `SyncMessage` encoded with `PropertyListEncoder` in binary format. Binary plist stores `Data` as raw bytes, so GPS records have no base64 overhead. Replies use the same format.

## Model

### Messages

```swift
/// Every message sent between the phone and the watch.
enum SyncMessage: Codable {
    case startRound(StartRound)
    case startRoundAck(StartRoundAck)
    case cancelRound(CancelRound)
    case endRequest(EndRequest)
    case endRound(EndRound)
    case endAck(EndAck)
    case streamBatch(StreamBatch)
    case streamAck(StreamAck)
    case holeTimeline(HoleTimelineMessage)
    case marks(MarksSnapshot)
}

struct StartRound: Codable {
    let roundID: UUID
    let date: Date
    let course: Data            // CourseSelection.trimmed, JSON, gzipped
    let holeTimeline: [HoleStart]
    let marks: MarksSnapshot
    let streamBase: Int         // first stream index for this round (nonzero when reactivated)
}

struct StartRoundAck: Codable { let roundID: UUID }
struct CancelRound: Codable { let roundID: UUID }
struct EndRequest: Codable { let roundID: UUID; let endedAt: Date }
struct EndRound: Codable { let roundID: UUID; let endedAt: Date; let lastSeq: Int? }  // nil = no records
struct EndAck: Codable { let roundID: UUID; let lastSeq: Int? }

struct StreamBatch: Codable {
    let roundID: UUID
    let from: Int               // index of the first record
    let records: Data           // StreamRecord records back to back; empty = probe
}

struct StreamAck: Codable {
    let roundID: UUID
    let have: Int?              // nil = phone does not know this round; watch deletes its stream
}

struct HoleTimelineMessage: Codable { let roundID: UUID; let entries: [HoleStart] }

struct MarksSnapshot: Codable {
    let roundID: UUID
    let version: Int
    let holes: [[BallMark]]     // marks per hole index
}
```

### Hole timeline

```swift
enum HoleStartSource: String, Codable {
    case roundStart     // first entry
    case autoAdvance    // HoleAdvancer found the tee
    case playHole       // user tapped "Play this hole"
    case estimated      // filled in for a skipped hole from the GPS track
    case corrected      // moved by the phone to fit the marks
}

struct HoleStart: Codable {
    let id: UUID
    let holeIndex: Int
    var startedAt: Date
    var source: HoleStartSource
    var version: Int    // the phone adds 1 each time it corrects the entry
}
```

- `Round` gets `holeTimeline: [HoleStart]`, sorted by `startedAt`. It starts with `HoleStart(0, round.date, .roundStart)`.
- `currentHoleIndex` becomes a computed property: the last entry's `holeIndex`.
- `holeIndex(at: Date)` returns the last entry with `startedAt <= date`.
- GPS fixes, swings, and swing guesses never store a hole. They always use `holeIndex(at:)`, so a corrected timeline fixes them automatically. Marks keep a fixed hole, because the user places them on a hole on purpose.
- `RoundStore.lastHoleChange` and its duplicate check are removed.

#### Rules

| # | Rule |
|---|---|
| 1 | **The hole only goes up over time.** Every entry's hole is higher than the one before it. Nothing appends a lower hole. A new entry timed before the last entry (the two clocks differ slightly) is placed just after it |
| 2 | **"Play this hole" is offered only for holes after the current hole**, on the phone and on the watch. Earlier holes can be viewed but not played |
| 3 | **A forward jump of more than one hole fills in the skipped holes** from the GPS track (below) |
| 4 | **Only the phone corrects entries.** The watch only creates them |

#### Merge

1. Union both lists by `id`. When both have the same `id`, keep the higher `version`.
2. Sort by `startedAt`.
3. Walk the list and drop any entry whose hole is not higher than the previous kept entry's hole (rule 1).

Both devices run the same steps, so they end with the same timeline. Example: the phone jumps 3→7 at 10:05, and the watch auto-advances 3→4 at 10:06 before it hears about the jump. Both devices drop the 4 entry.

Both clocks use network time, so ordering by `startedAt` across devices is close enough.

#### Filling in skipped holes

Runs on the phone (it has the watch GPS) when an entry jumps more than one hole. Example: stuck on hole 3, the user taps "Play hole 7" at 10:40.

```
timeline: (3, 9:50) ─────────── gap ───────────▶ (7, 10:40)
GPS track 9:50–10:40, scanned in hole order:
  first fix on or within 20 m of hole 4 tee  → (4, 10:02, estimated)
  first fix on or within 20 m of hole 5 tee  → (5, 10:15, estimated)
  first fix on or within 20 m of hole 6 tee  → (6, 10:27, estimated)
```

- Each hole's scan starts after the previous hole's time.
- A swing within 20 m of the tee is used first when there is one, since it is likely the tee shot.
- A hole that can't be placed gets no entry. Its data counts toward the hole before it until the user sets a time, or until a mark corrects it.
- The result goes to the watch as a normal timeline message.

#### Confirmation from marks

Confirmation is worked out, not stored, so it always matches the current marks. A mark on hole k proves the player was on hole k at that moment, so hole k's start must fall in this window:

```
last mark on hole k-1          first mark on hole k
        │◀──── hole k must start in here ────▶│
```

| Entry start time | Meaning | Action (phone only) |
|---|---|---|
| Inside the window | Confirmed | None |
| Before the last mark on hole k-1 | Auto-advance fired early | Correct it |
| After the first mark on hole k | Late (the user tapped Play late) | Correct it |
| Hole k has no mark yet | Not confirmed | None |

Correct it: scan the GPS inside the window for the first fix within 20 m of hole k's tee (a swing first, as above). If none is found, use the first mark's time on hole k. Set `source = .corrected`, add 1 to `version`, and send the timeline.

The check runs after every mark change and after every timeline change. The round view marks unconfirmed `estimated` entries as "estimated" and lets the user set their start time (a correction by the user, same fields).

### Round status

`isActive` is replaced by `status`:

| Status | Phone | Watch |
|---|---|---|
| `starting` | Waiting for `StartRoundAck` | – |
| `active` | Recording and syncing | Recording |
| `ending` | Waiting for GPS up to `lastSeq` | – |
| `ended` | Done | Done. Stream kept until the phone acks it |

No migration from `isActive` (see No compatibility code).

Each round also stores `endedAt: Date?`. The phone drops stream records with a timestamp after `endedAt`.

### Marks version

- Each phone `Round` stores `marksVersion: Int`, saved with the round.
- Every add, move, type change, reorder, or delete of a mark adds 1 and sends a `MarksSnapshot` with every mark in the round.
- The watch stores the version it last applied. It applies a snapshot only if `version` is higher, and then replaces all marks of the round.
- `StartRound` carries the current snapshot.

## Stream (watch → phone)

### Records

The watch writes one stream file per round: `<roundID>_watch.stream`. It is an append-only list of fixed-size records.

| Byte | Field |
|---|---|
| 0 | Kind: `0` = GPS fix, `1` = swing |
| 1–24 | GPS fix: the existing 24-byte `TrackPoint` record. Swing: timestamp (Int64 ms), peak force in g (Float32), then 12 zero bytes |

- Record size: 25 bytes.
- A record's index = `streamBase` + its position in the file.
- The phone stores the same records in the same kind of file, as received. Its `have` is its record count, so it can't drift from what is on disk.
- `StreamStore` replaces `TrackStore`. The phone stopped recording its own GPS before this change, so the old `.phone` track and `TrackSource` are removed.
- `StreamStore.points(for:until:)` and `StreamStore.swings(for:until:)` read fixes and swings (timestamp and peak force) from the stream file. There is no separate `SwingStore`.

### Phone rule for each batch

| Case | Check | Action | Reply |
|---|---|---|---|
| Unknown round | Round not found (deleted or canceled) | Discard | `StreamAck(have: nil)` |
| Next in line | `from == have` | Append | `have + count` |
| Overlap (resend) | `from < have` | Skip records below `have`, append the rest | New `have` |
| Gap | `from > have` | Discard the whole batch | `have` (unchanged) |
| After `endedAt` | Record timestamp > `endedAt` | Stored like any other record | New `have` |

The phone writes records to disk **before** it replies.

Records after `endedAt` are stored, not dropped: dropping one would shift every later index and break `have`. Every read of a round's fixes and swings stops at `endedAt` instead. When the watch's `lastSeq` arrives, the phone removes any records after it.

### Watch sender

```
new record appended ─▶ batch in flight? ── yes ─▶ wait
                           │ no
                           ▼
                  phone reachable? ── no ─▶ wait for reachability change
                           │ yes
                           ▼
       send StreamBatch(from: cursor, records cursor..<end, max ~40 KB)
                           │
          ┌────────────────┴────────────────┐
     reply StreamAck(have)             error / timeout
     cursor = have                     cursor unchanged
     have == nil → delete stream       retry on next record,
     more records? → send again        reachability change, or 10 s timer
```

- One batch in flight across all rounds. Rounds that are not fully acked are sent oldest first.
- Cursor unknown (app launch): send an empty probe batch. The reply gives `have`.
- Reply `have` ≥ the watch's record end: nothing to send.
- After the round is `ended` on the watch and `have` > `lastSeq`: delete the stream file. This is checked on every reply and when the round ends.

### Phone catch-up

When the session activates and on each reachability change, the phone sends `StreamAck(roundID, have)` for each round that is `active` or `ending`. The watch sets its cursor and sends.

### Swings to guesses (phone)

For each new swing record:
1. Location: the watch GPS fix nearest in time, within 5 s. No fix → no guess.
2. Hole: `round.holeIndex(at: swing.timestamp)`.
3. Add `MissedMarkGuess(reason: .swing)` to the phone `GuessStore` (the cap of 10 per hole stays).

A swing that arrives before its GPS fix is checked again when more fixes arrive.

## Start round (phone → watch)

```
Phone                                              Watch
─────                                              ─────
Tap Start Round
round = Starting ("Starting on watch…" + Cancel)
HKHealthStore.startWatchApp ─────────────────────▶ app launches, workout starts
StartRound(id, course, timeline, marks, streamBase) ─▶
  (one message, or chunks)                         already another active round?
                                                     → end it (watch-started end flow)
                                                   create round, status = active
                                                   start GPS + swing detection
round = Active ◀─────────────── StartRoundAck(id) ─
no ack in 15 s → [Retry] [Cancel]
```

- Button enabled: `WCSession.isPaired && isWatchAppInstalled` (UI tests are exempt, as today).
- Until the ack, the phone sends no other messages for the round and records nothing.
- Retry: sends the whole `StartRound` again. A duplicate is safe (same round ID).
- Cancel: deletes the round on the phone and sends `CancelRound` (`sendMessage` and `transferUserInfo`). If the watch did start it, the watch ends it and deletes its stream.
- Reactivating an ended round sends `StartRound` with the same ID and `streamBase` = the phone's `have`.

### Chunks

Used only when the encoded `StartRound` is larger than 60 KB.

- Every chunk carries `transferID`, `index`, `totalChunks`, and the data. There is no separate header, so a lost or late header can't drop chunks.
- Every chunk is sent with a reply handler. The watch replies with an empty ack for each chunk, and with `StartRoundAck` in place of that ack once all chunks are in and the round is active.
- Any chunk error or no ack in 15 s: the phone resends all chunks with a new `transferID`. The watch drops unfinished transfers older than 60 s.

## End round

### Phone starts it

```
Phone                                              Watch
─────                                              ─────
User taps End Round
round = Ending
  UI: "Syncing watch data…" + [Force end]
  │
  ├─ EndRequest(roundId, endedAt) ───────────────▶ stop GPS + swing detection
  │    (sendMessage with reply)                    drop records after endedAt
  │                                                flush stream to disk
  │                                                end workout
  │                                                round = Ended
  │  ◀───────────────────────────── EndAck(lastSeq) ── lastSeq = last record index
  │
  │  ◀─────────────── StreamBatch(from: have, [..]) ── stream keeps draining
  ├─ StreamAck(have) ────────────────────────────▶ (repeats until have > lastSeq)
  │
have > lastSeq
round = Ended                                      watch deletes its stream file

── If the EndRequest send fails (watch unreachable) ──
Phone: stays Ending
       also queues EndRequest with transferUserInfo, so the watch
         gets it the next time its app runs
       resends with sendMessage on every reachability change
[Force end] → round = Ended now; later records up to endedAt are still accepted
Duplicate EndRequest → the watch is already Ended and replies with the same lastSeq
```

If the phone holds records past `lastSeq` (they arrived before the watch dropped them), it removes them.

### Watch starts it

```
Phone                                              Watch
─────                                              ─────
                                                   User taps End Round
                                                   stop GPS + swing detection
                                                   flush stream to disk
                                                   end workout
                                                   round = Ended (on the watch)
                                                   lastSeq = last record index
round = Ending ◀── EndRound(roundId, endedAt, lastSeq) ──
  UI: "Syncing watch data…"                        (sendMessage with reply;
  │                                                 wakes the phone app)
  ├─ EndAck ─────────────────────────────────────▶
  │
  │  ◀─────────────── StreamBatch(from: have, [..]) ── stream keeps draining
  ├─ StreamAck(have) ────────────────────────────▶ (repeats until have > lastSeq)
  │
have > lastSeq
round = Ended                                      watch deletes its stream file

── If the EndRound send fails (phone unreachable) ──
Watch: already Ended; nothing waits on the phone
       also queues EndRound with transferUserInfo
       resends with sendMessage on every reachability change until acked
Phone gets it later → Ending → drains the stream → Ended
```

### Both end at the same time

Each receiver is already Ending or Ended. It replies to the other device's message and moves on. The watch's `lastSeq` is final in both cases.

## Snapshots

| Snapshot | Sender | Sent when | Receiver rule |
|---|---|---|---|
| `HoleTimeline` | Both | Every hole change or correction | Merge (see Hole timeline) |
| `MarksSnapshot` | Phone | Every mark change | Apply only if `version` is higher |

- Sent by `sendMessage` (no need to wait for the reply) when reachable.
- Always also written to `updateApplicationContext` as `["m": <encoded context>]`, where the context holds the active round's latest timeline and marks snapshot.
- Messages for a round the receiver doesn't have are ignored.

## Service structure

All sync logic is in `Shared/`, so the unit tests can run a phone and a watch side by side through a fake transport.

| Type | File | Job |
|---|---|---|
| `SyncMessage` + message structs | `Shared/Models/SyncMessage.swift` | The model objects |
| `HoleStart`, `HoleTimeline` | `Shared/Models/HoleStart.swift` | Timeline entries, merge, hole at a time |
| `StreamRecord`, `Swing` | `Shared/Models/StreamRecord.swift` | 25-byte stream records |
| `SyncCodec`, `ChunkAssembler` | `Shared/Services/Sync/SyncCodec.swift` | `SyncMessage` ↔ `["m": Data]`; chunk split and join |
| `SyncTransport`, `WatchConnectivityTransport` | `Shared/Services/Sync/SyncTransport.swift` | Wraps `WCSession`. Tests use `FakeTransport` |
| `SyncService` | `Shared/Services/SyncService.swift` | The one entry point: send, queue, context, chunking, hands incoming messages to its `handler` |
| `PhoneSync` | `Shared/Services/Sync/PhoneSync.swift` | Phone: start handshake (timeout, Retry, Cancel, `startWatchApp`), end flows (Force end), receiving the stream, running the timeline fixer |
| `WatchSync` | `Shared/Services/Sync/WatchSync.swift` | Watch: taking a start, recording, end flows |
| `StreamSender` | `Shared/Services/Sync/StreamSender.swift` | Watch: cursor, one batch in flight, probe, 10 s retry |
| `StreamReceiver` | `Shared/Services/Sync/StreamReceiver.swift` | Phone: the rules for each batch; swings to guesses |
| `SnapshotSync` | `Shared/Services/Sync/SnapshotSync.swift` | Timeline and marks messages, application context |
| `StreamStore` | `Shared/Services/StreamStore.swift` | Reads and writes stream files |
| `HoleTimelineFixer` | `Shared/Services/HoleTimelineFixer.swift` | Fills in skipped holes and corrects entries from marks |
| `SwingPeakFinder` | `Shared/Utilities/SwingPeakFinder.swift` | Finds swings and their peak force in accelerometer readings |

`RoundStore` no longer has `fromSync` flags. It reports changes made on this device through `onTimelineChanged` and `onMarksChanged`, and `PhoneSync` or `WatchSync` decides what to send.

UI tests run the phone without a watch, so `PhoneSync(requiresWatch: false)` starts and ends rounds on the phone alone under `--ui-testing`.

## Watch changes

- `SwingDetector` uses `CMBatchedSensorManager` accelerometer batches during the workout. It checks each batch for readings of 10 g or more (3 s cooldown) and writes a swing record to the stream with the highest force seen in the swing.
- Removed: `BreadcrumbRecorder`, the watch `GuessStore`, the watch `SettingsStore`, guess creation in `WatchRoundView`.
- `WatchAppDelegate` handles `handle(_ workoutConfiguration:)` (the launch from `startWatchApp`) by starting the workout. If no round arrives within 60 s, it stops the workout.
- `WatchAppDelegate` starts and stops GPS, the workout, and swing detection whenever the active round changes, so this works with no view on screen.
- Marks on the watch are read-only and come from `MarksSnapshot`. "Previous" reads them.
- The hole arrows work like the phone: they only change `viewingHoleIndex` and pause auto-advance. While viewing another hole, the watch shows "Resume round", plus "Play this hole" when the viewed hole is after the current hole.

## Phone changes

- `RoundListView.canStartRound` uses paired + installed. The Starting and Ending states are shown with Cancel, Retry, and Force end.
- Add the HealthKit entitlement to the iOS target (needed for `startWatchApp`).
- `RoundMapView` mark edits go through `RoundStore`, which bumps `marksVersion`.
- `MarkSuggester` stays as it is. Swing guesses come from `StreamReceiver`.
- "Play this hole" shows only when the viewed hole is after the current hole.
- The round view lists the timeline, marks `estimated` entries, and lets the user set an entry's start time.
- A new `HoleTimelineFixer` fills in skipped holes and corrects entries from marks. It runs after every timeline change, mark change, and stream batch, because GPS for a skipped hole can arrive after the jump.
- The map's track for a hole is the fixes the timeline puts on that hole. `MarkSuggester.holePoints`, which guessed the hole from the course shape, is removed.
- The clock button (bottom right during a round, toolbar for past rounds) opens Hole Times.
- `MissedMarkGuess` no longer has `holeIndex` or `reason`. Its ID comes from the round and the swing time, so the same swing never makes two guesses. `GuessStore` remembers removed guesses, so they never come back.
- CSV export (`TrackExporter`) adds one `swing` row per swing and a `peakG` column:

| Column | Swing row value |
|---|---|
| `type` | `swing` |
| `timestamp` | Swing time |
| `latitude`, `longitude` | The watch GPS fix nearest in time (blank if none within 5 s) |
| `source` | `watch` |
| `hole` | From the hole timeline (1-based) |
| `peakG` (new, last column) | Highest force in the swing. Blank on other rows |
- Settings sync is removed (`SettingsView` no longer sends).

## No compatibility code

The app has not been released, so rounds, tracks, and guesses saved by earlier builds are junk.

- No migration, no fallback decoding, no version fields for saved files, no support for old message formats.
- If saved data can't be read, it is discarded and the app starts empty.
- `LossyRound` in `RoundStore` is removed. A failed load starts with no rounds.
- The phone and the watch are always built and installed together, so messages need no version field.

## Tasks

Branch: `feature/unified-messaging`.

1. Message models, `SyncCodec` (binary plist, chunk split/join), and codec tests.
2. `SyncTransport` protocol, `WCSession` wrapper, and a fake transport that can connect two services and drop, duplicate, delay, or reorder messages.
3. `Round.status`, `endedAt`, `holeTimeline`, and `marksVersion`. Tests.
4. Hole timeline: `HoleStart`, merge (version, the hole only goes up), `holeIndex(at:)`. Replace every `currentHoleIndex` write. Forward-only "Play this hole" on the phone and the watch, and watch arrows that only change the viewed hole. Tests: the phone and the watch changing at once, a lower hole dropped, a higher version wins.
4a. `HoleTimelineFixer`: fill in skipped holes from the GPS track and swings, and correct entries from marks. Tests: stuck-then-jump, early auto-advance, late Play tap, hole with no tee fix, mark deleted.
5. `StreamStore` (25-byte records) and moving the watch track to it. Tests.
6. `StreamSender` and `StreamReceiver`. Tests: next in line, overlap, gap, probe, unknown round, records after `endedAt`, reply lost, batch lost.
7. `CMBatchedSensorManager` swing detection writing swing records. Swing → guess on the phone. Tests for the guess lookup.
8. Start round handshake, including chunks, `startWatchApp`, Retry, and Cancel. Tests: ack, timeout, lost chunk, duplicate start, other round already active on the watch.
9. End round, both flows, with the `transferUserInfo` backup and Force end. Tests: both flows, unreachable, duplicates, both ending at once.
10. Snapshots with application context. Tests: out-of-order marks, duplicates, lost snapshot, timeline conflict.
11. Remove the old messages, outbox, `transferFile` path, `BreadcrumbRecorder`, watch `GuessStore`, settings sync, and `LossyRound`.
11a. CSV export: swing rows and the `peakG` column. Tests.
12. UI: Starting, Ending, Retry, Cancel, Force end. Update the UI tests.
13. Check on real devices (below).

## Check on real devices

| Question | Why it matters | If the answer is no |
|---|---|---|
| Is the phone → watch `sendMessage` reachable while the watch app is in the background during a workout? | Snapshots and `EndRequest` sent quickly | They arrive through application context and `transferUserInfo`, just slower |
| Are `transferUserInfo` and application context delivered to a watch app running in the background? | Backup delivery during a round | Deliver on the next foreground |
| ~~How big is a typical trimmed, gzipped course?~~ Answered by `SyncFlowTests`: Broadlands (18 holes) is 95.6 KB, so chunks are needed | Whether Start round needs chunks at all | Chunks stay |
| Battery use of sending on every GPS fix | The chosen send rate | Add a minimum time between batches |
| `CMBatchedSensorManager` detects swings at the 10 g limit | Swing detection works | Tune the limit using recorded batches |
