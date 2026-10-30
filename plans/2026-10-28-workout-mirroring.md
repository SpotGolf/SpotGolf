# Workout Mirroring for Round Messages

## Problem

During a round the phone falls behind the watch, and the GPS track stops showing. It catches up when the watch screen turns on.

Every round message goes through WatchConnectivity's `sendMessage`, which needs `isReachable`. Nothing sends while the watch says the phone is not reachable. `StreamSender.pump()` returns, and `WatchConnectivityTransport.send` fails at once. Nothing is queued.

## Decision

Send round messages over HealthKit workout mirroring whenever the mirrored session is connected. Apple built it to carry live data between the watch's workout and the phone during a workout. WatchConnectivity stays as the fallback, and for everything outside a running workout.

A probe on the phone and watch (2026-10-28, 5.5 minutes) showed mirroring starting within 1 s of the workout and losing none of 64 heartbeats. Lag was 0 to 0.2 s, with a worst case of 5 s.

## What Apple and developers say

| Finding | Source |
|---|---|
| HealthKit launches the phone app in the background to hand it the mirrored session. `workoutSessionMirroringStartHandler` must be set at launch | Apple docs, WWDC23 10023 |
| The phone app needs the `workout-processing` background mode. Without it HealthKit never hands it the mirrored session: on 2026-10-29 the watch's start succeeded and the phone's start handler never ran | Real devices, 2026-10-29 |
| After a disconnect, the watch does not reconnect by itself. Calling `startMirroringToCompanionDevice` again on the same running session works: the phone's start handler is called with a new session, 12 to 41 s later | Real devices, 2026-10-29 |
| The phone's mirrored session never carries data again once it ends or disconnects. Sends on it fail with "Workout session is not currently mirroring to the companion device" | Real devices, 2026-10-29 |
| iOS can get stuck: the watch's start succeeds and the phone's start handler never runs, until both devices restart. Rounds then go over WatchConnectivity | Real devices, 2026-10-29; Developer Forums 782370, 804276 |
| Each workout is saved to Fitness, so a new workout is never started just to get mirroring back | `WorkoutManager.sessionFinished` |
| Mirroring fails on a session that has ended. A new session must call `startMirroringToCompanionDevice` again | Apple docs |
| Data goes both ways. No size limit, ordering, or queuing is documented. A send while disconnected fails | Apple docs |
| iOS 26.0 to 26.1: mirroring dropped soon after it started. Apple DTS suggested starting mirroring only once the session is running | Developer Forums 804276 |
| Mirroring is not supported on simulators (Apple DTS, Developer Forums 765469). A probe on a simulator pair (2026-10-28, Xcode 27) matched: `startMirroringToCompanionDevice` reported success, every send failed with HealthKit error 300, and the phone's start handler never ran | Forums 765469, probe |

## Message routing

| Message | Channel |
|---|---|
| `send` (start, start ack, end request, end round, stream batch, stream ack, display hole, pins, strokes, settings, chunks) | Mirroring when connected, else WatchConnectivity `sendMessage` |
| `queue` (backup end round and end request, cancel, round deleted, phone settings, putt session, send log) | WatchConnectivity `transferUserInfo`, unchanged |
| `updateContext` | WatchConnectivity application context, unchanged |
| `transferFile` (log chunks, Putt Lab sessions) | WatchConnectivity, unchanged |

`PhoneSync`, `WatchSync`, `StreamSender` and `SnapshotSync` do not change. The change is below `SyncService`, in the transport.

## Design

```
SyncService ──▶ RoutingTransport (SyncTransport)
                  │ send:
                  ├─ mirror connected? ── yes ─▶ MirrorTransport ─▶ sendToRemoteWorkoutSession
                  │                                   │ failure ─▶ mark disconnected, send again over WC
                  └─ no ─────────────────────────▶ WatchConnectivityTransport.send
                  │ queue, updateContext, transferFile ─▶ WatchConnectivityTransport
                  │ isReachable = mirror connected || WC reachable
```

### `MirrorTransport` (Shared)

- Holds the current `HKWorkoutSession`: the primary session on the watch, the mirrored one on the phone. `attach(_:)` replaces it, and `detach()` clears it.
- Mirroring has no reply. Each send is wrapped in an envelope, `MirrorEnvelope { id: UUID, inReplyTo: UUID?, payload: Data }`, as a binary property list.
  - Request: `inReplyTo` is nil. The receiver passes `payload` to `delegate.transport(didReceive:)` and always sends a reply envelope back, even an empty one, so the sender's `reply` runs. That matches `sendMessage`.
  - Reply: matched to the waiting send by `inReplyTo`.
  - Hello: a request with an empty payload. The receiver replies and does not pass it to the delegate.
- Same rules as `WatchConnectivityTransport`: one send in flight, `maxWaiting` 20, `sendTimeout` 30 s. Exactly one of `reply` or `failure` runs.
- **Connected only once data has come back.** A successful `startMirroringToCompanionDevice` does not mean the link works: on simulators it succeeds and every send fails. So `isConnected` turns true only when an envelope arrives from the other side. It turns false on a send error, on `didDisconnectFromRemoteDeviceWithError`, or when the session ends. Every change calls `delegate.transportReachabilityChanged()`, so the existing reachability code (stream pump, start retry, stream ack) runs on mirroring changes too.
- While attached and not connected, the watch sends a hello on attach and on each watchdog check. The phone's reply makes the watch connected, and the hello makes the phone connected. On simulators every hello fails, `isConnected` stays false, and every message goes over WatchConnectivity, as today.
- HealthKit calls the session delegate and send completion on its own queue. Those closures are `@Sendable` and hop to the main actor (see the Swift 6 framework callback rule).
- A test seam, `MirrorChannel` protocol (`send(Data) async throws`, incoming data callback), stands in for `HKWorkoutSession` in tests, since mirroring does not run on simulators.

### `RoutingTransport` (Shared)

- Implements `SyncTransport` over a `MirrorTransport` and a `WatchConnectivityTransport`. `SyncService`'s default transport becomes this.
- `send` uses mirroring when `isConnected`. If that send fails with a disconnect (not a timeout), the same payload is sent once over WatchConnectivity. A timeout reports failure as today, since the other side may have received it. Every caller already copes with a repeated message.
- Logs the channel once per change, `Sync channel: mirroring` or `Sync channel: WatchConnectivity`, not per send.
- Forwards both transports' delegate calls to `SyncService`.

### Watch

- `WorkoutManager` calls `startMirroringToCompanionDevice()` when its session reaches `.running` (the DTS advice). That covers a new workout, a recovered one, and each watchdog restart or Restart Sensors. It hands the session to `MirrorTransport.attach`, and calls `detach` in `sessionFinished`.
- A failed `startMirroringToCompanionDevice` is logged, and mirroring is tried again on the watchdog's next check while the session runs. The round goes on over WatchConnectivity meanwhile.
- Mirroring is only ever started again on the same running session, never by starting a new workout. `MirrorRestart` decides when:
  - At once on a new session, and after a failed start.
  - On the watchdog's check, after 60 s disconnected and 60 s since the last start.
  - When the phone becomes reachable over WatchConnectivity (`WatchServices` calls `WorkoutManager.phoneBecameReachable`), after 15 s disconnected and 15 s since the last start. The phone is then likely back in range.
- Logging: the first hello's result after each attach or disconnect, and each restart on the same session, but only once mirroring has been connected. On simulators it never connects, so nothing repeats in the log.
- **End of round.** Today the workout stops as soon as the round ends, which also ends mirroring while `EndRound` and the last records are going out. The workout now keeps running after the round ends until the end handshake below is done, or for 60 s at most. The handshake uses the messages that exist now:

  ```
  Phone ends:   Phone ──EndRequest──▶ Watch ──EndAck(lastSeq)──▶ Phone
  Watch ends:   Watch ──EndRound(lastSeq)──▶ Phone ──EndAck──▶ Watch
  Then:         Watch ──StreamBatch…──▶ Phone ──StreamAck(have)──▶ Watch
                when have > lastSeq, the watch deletes the stream and stops the workout
  ```

  `lastSeq` is the watch's "this is everything" mark, so no new finished message is needed. Sensors and location still stop at once. `activeRoundChanged(false)` stops everything but the workout, and a new `WatchServices` step stops the workout when `StreamSender.onStreamDeleted` fires or the 60 s run out. After 60 s, the existing `transferUserInfo` copy of the end, and the stream over WatchConnectivity, finish the job later, as they do today.
- Drill sessions (Putt Data Sharing) run a workout too, so they mirror as well. Nothing uses it there. Their notices and files stay on WatchConnectivity.

### Phone

- The phone app declares the `workout-processing` background mode (`UIBackgroundModes` in `project.yml`).
- `PhoneServices.init` sets `workoutSessionMirroringStartHandler` on the shared `HKHealthStore` before anything else, since HealthKit may launch the app in the background for it (for example after iOS ends the app mid-round). Each call attaches the new session, replacing any old one.
- When the phone's mirrored session ends or disconnects, `WorkoutSessionChannel` calls `MirrorChannel.onEnd`, and `MirrorTransport` detaches it, since it can never carry data again. That stops the hellos on it.
- The phone never ends the mirrored session. The watch ends it.
- `PhoneSync.reachabilityChanged` already resends the start and the stream ack when the watch becomes reachable. With mirroring it runs once the mirrored session is connected, so `startRound` goes out about 1 s after the workout that `startWatchApp` launched starts.

### Size

`SyncCodec.maxMessageBytes` (60 KB) and chunking stay for both channels. A 95.6 KB Broadlands start goes as 2 chunks. If a chunk of this size does not go over mirroring (check 1 below), mirroring gets its own smaller chunk size.

## Steps

1. `MirrorEnvelope` and `MirrorTransport` with the `MirrorChannel` seam. Tests: request and reply, empty reply, hello, not connected until an envelope arrives, timeout, one in flight, disconnect fails waiting sends, reachability change on connect and disconnect.
2. `RoutingTransport`. Tests: mirroring chosen when connected, WatchConnectivity when not, fallback once on a disconnect failure, no fallback on a timeout, `queue`, `updateContext` and `transferFile` always on WatchConnectivity.
3. Watch: start mirroring on `.running`, attach and detach, hello and retry on the watchdog, and restart mirroring on the same session as `MirrorRestart` says. Tests in `MirrorRestartTests`.
4. Watch: keep the workout running after the round ends until the stream is complete, or 60 s. Tests in `SpotGolfWatchTests` for both endings.
5. Phone: the `workout-processing` background mode, the mirroring start handler in `PhoneServices.init`, and detaching an ended session. Tests in `MirrorTransportTests`.
6. Update `SyncTestSupport`'s fake transport so the existing sync flow tests run over `RoutingTransport`, once with mirroring connected and once with it disconnected.
7. Simulators: run a round on a clone pair with `replay-round.py` for a few holes. Every message goes over WatchConnectivity, and the log shows no `Sync channel: mirroring`.
8. Real devices (below).

## Check on real devices

Mirroring only runs on the real iPhone and watch. The checks ran on 2026-10-29 at home, on Test Course. After each one, the phone's log was pulled with `devicectl`.

| # | Do | Pass | Result |
|---|---|---|---|
| 1 | Start a round from the phone, with the watch app not open. Keep the watch wrist down, so its screen stays off, and walk for a few minutes holding the phone | The track on the phone keeps up. The log shows `Sync channel: mirroring` within a few seconds of the start | Passed. Mirroring connected about 1 s after the watch's workout started, and stayed up for 4 minutes with the screen off |
| 2 | In the same round, leave the phone in the house and walk out of Bluetooth range (the watch shows a red iPhone icon) for 2 minutes, then come back | The track fills in the walk. The log shows the disconnect, then `Sync channel: mirroring` again | Passed. The track had no gaps. Mirroring came back 14 to 19 s after the phone was reachable again |
| 3 | In the same round, tap Restart Sensors on the watch's end-round page | The log shows mirroring starting again on the new workout. The track keeps updating | Passed. Restart Sensors is a debugging aid that will be removed |
| 4 | End the round on the phone | The log shows the watch stopping the workout after the last stream ack, not after 60 s | Passed. The workout stopped 4 s after the end |
| 5 | Start a second short round and end it with End Round on the watch | Same as 4 | Passed. The phone's mirrored session ended 8 s after the end |

Not yet checked on real devices: a start large enough to be split into chunks (Broadlands, 95.6 KB in 2 chunks) over mirroring. Every check used Test Course.
