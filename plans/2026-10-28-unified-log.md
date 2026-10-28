# Unified log

Prepares the log for launch. The log is only for debugging: when users hit a bug, they send it to us. Replaces the per-round log in `plans/2026-10-10-app-log.md`.

| Today | After |
|---|---|
| Lines saved in SwiftData (`LogEntry`), grouped by round | One text log on the phone, rotated by size, 10 MB in all |
| Watch sends only round lines, inside `StreamBatch` | Watch sends every line in chunks with `transferFile`, as Putt Sharing does |
| Debug Logging setting | Removed. `debug` lines are always written |
| Log viewer in Settings | Removed. Settings has "Share logs…", which shares the log gzipped |

## Line format

`LogLine` gets `roundID: UUID?`, set when the line is written: the current round on the phone, the active round on the watch. The 5-minute move of pre-round lines into the round goes away: the log is in one place, so what came before a round is right above it.

One line of text each. The round column is `-` outside a round, so every line has the same number of columns before the message:

```
2026-10-09T16:12:33.123Z watch E sensors 6F1C…-…A2 accelerometer stopped on an error; restarting
2026-10-09T16:15:02.004Z phone N sync - Watch reachable
```

Columns: timestamp, device, level letter (`D`, `N`, `E`, `F`), category, round ID or `-`, message. Newlines in a message are written as `\n`, and backslashes as `\\`, so each line stays one line and reads back exactly.

## Phone: `LogFile`

A new `LogFile` (in `Shared/Services`) replaces `LogStore` as `Log`'s sink on the phone.

| Part | Behaviour |
|---|---|
| Location | `Application Support/Logs/`, files `spotgolf.log` (current), `spotgolf.1.log` … `spotgolf.4.log` (older) |
| Writing | Appends each line at once through a `FileHandle`, behind a lock. Any thread, no main actor. Lines are events only, so there is no need to batch them |
| Rotation | Before a write that would take `spotgolf.log` past 2 MB: delete `.4`, rename `.3`→`.4` … current→`.1`, start a new current. 5 files × 2 MB = 10 MB |
| Watch lines | Appended as they arrive from the watch, so they sit near, not exactly at, their time order. Each has its own timestamp |
| Failure | If the file cannot be opened or written, the line still goes to Apple's unified log; the file error is logged there once, not into the file |

`Log`'s hold-until-sink-is-set buffer stays as it is.

## Watch: log chunks sent as files

The watch has no share screen, so its log only needs to hold lines until the phone has them. It sends them the way Putt Sharing sends sessions: `transferFile`, which the system queues, retries and delivers even when the phone app is not running.

```
Log.x.notice(...) ─▶ watch LogFile (Logs/spotgolf.log)
  chunk closes ─▶ moved to Logs/outbox/<yyyyMMdd-HHmmss>-<uuid>.log
  outbox chunk ─▶ transferFile, metadata { chunk: name }
                    ─▶ phone appends its lines to its LogFile, remembers the name
  didFinishFileTransfer, no error ─▶ watch deletes the chunk
  launch ─▶ sends again every outbox chunk not in outstandingFileTransfers
```

| Part | Behaviour |
|---|---|
| Writing | The same `LogFile` as the phone, with one current file and no numbered files: closing a chunk takes the place of rotation |
| Closing a chunk | When the current file reaches 50 KB, when its first line is 5 minutes old (checked on the next write and by a 1-minute timer while lines are waiting), when a round ends, and when the phone asks |
| Phone asks | "Share logs…" queues a `sendLog` message. The watch closes its chunk and sends it. Nothing waits for it: lines that arrive later are in the next share |
| Outbox cap | 1 MB. Past it, the oldest chunks are deleted, so a watch that cannot reach the phone for days does not fill up |
| Duplicates | A kill after a chunk arrives but before `didFinish` sends it again at launch. The phone keeps the last 100 chunk names in `UserDefaults` and skips a name it has seen |
| Failed transfer | `didFinish` with an error keeps the chunk; the next launch sends it again, as Putt Sharing does |
| Phone side | `SyncService.fileHandler` routes a file by its metadata: a `chunk` key goes to the log, the session keys to Putt Sharing. The phone appends the chunk's text to its `LogFile` as is, then deletes the file |

## Removed

| What | Where |
|---|---|
| Debug Logging toggle and `SettingsKey.debugLogging` | `SettingsView`, `SettingsKey`, `PhoneServices` |
| `Log.isDebugEnabled` | `Log`, `WatchServices`, `WatchSync` |
| `debugLogging` | `StartRound`, `RoundSettingsMessage`, `PhoneSync`, `WatchSync.debugLoggingKey` |
| Log fields of the stream: `logsFrom`, `logs`, `haveLogs`, `logBase`, `logCursors`, `logEnd` | `StreamBatch`, `StreamAck`, `StartRound`, `Round`, `StreamSender`, `StreamReceiver`, `PhoneSync`, `WatchSync` |
| Deleting a round's log with the round | `RoundListView`, `CloudSync`, `PhoneSync`, `WatchSync`, `StreamSender`. Lines age out by rotation instead |
| `LogView` and its export | `SpotGolf/Views/LogView.swift` |
| The round's Log buttons: on the map, and in the swipe actions of the active and past rounds' rows | `MapButtonBar`, `RoundMapView`, `RoundListView` |
| `LogEntry` and `LogStore` | `Shared/Models/LogEntry.swift`, `Shared/Services/LogStore.swift`, `Storage.models`, `PhoneServices`, `WatchServices` |

The data is not in production, so no migration: old stores lose the `LogEntry` table and the old message fields go without decode fallbacks.

## Settings

The Log section becomes:

| Part | Content |
|---|---|
| Button | "Share logs…" |
| Footer | "What the phone and watch apps recorded, for sending to SpotGolf support if something goes wrong." |

Tapping it:

1. Queues `sendLog` to the watch (no wait; whatever arrives later is in the next share).
2. On a background task, reads `spotgolf.4.log` … `spotgolf.log` oldest first and gzips them into one file, `SpotGolf-log-<yyyy-MM-dd-HHmm>.log.gz`, in the temporary directory.
3. Shows the share sheet (`ShareSheet`, as the track export does). A spinner on the button while it works.

Gzip: `Data.gzipCompressed()` from CourseDataSwift, which the round archive already uses. `LogShare` writes the file.

Some lines log course names and coordinates, so the footer makes no promise about location.

## Scripts

`Scripts/export-round.py` reads `ZLOGENTRY` from both stores. It changes to read `Logs/spotgolf*.log` from both containers, and the watch's unsent chunks in `Logs/outbox`, keep the lines whose round column is the round's ID or whose time falls in the round, and write the same `log.csv`.

## Tests

| Test | Checks |
|---|---|
| `LogTests` | `debug` is always written; held lines reach the sink; a line's text has the round column and escapes newlines |
| `LogFileTests` | Appends; rotates at the size limit; keeps 5 files, deleting the oldest; reads all files oldest first |
| `LogFileTests` (share) | The shared file inflates back to every log file, oldest first |
| `LogChunkTests` | The watch closes a chunk at 50 KB and at 5 minutes; an empty log sends nothing; the 1 MB outbox cap; a finished transfer deletes the chunk, a failed one keeps it. The phone adds a chunk once, ends it with a newline, and remembers the last 100 names |
| `SyncCodecTests` | `sendLog` round trip; `StreamBatch`, `StreamAck`, `StartRound` without log fields |
| `SyncFlowTests` | A watch chunk's lines reach the phone file, in and out of rounds; chunks arrive in order; `sendLog` closes the watch's chunk; launch sends again only chunks not on their way |
| `OutsideRoundUITests` | "Share logs…" shows the share sheet with the file; no Debug Logging toggle |

Then a round on the real phone and watch, and a share of the log by AirDrop.

## Version

A `feat` and a breaking change to watch messages, MINOR before 1.0.0.
