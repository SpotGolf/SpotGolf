# Workout Mirroring for Round Messages

## Problem

During a round the phone falls behind the watch, and the GPS track stops showing. It catches up when the watch screen turns on.

Every round message goes through WatchConnectivity's `sendMessage`, which needs `isReachable`. Nothing sends while the watch says the phone is not reachable. `StreamSender.pump()` returns, and `WatchConnectivityTransport.send` fails at once. Nothing is queued.

## Decision

Send round messages over HealthKit workout mirroring whenever the mirrored session is connected. Apple built it to carry live data between the watch's workout and the phone during a workout. WatchConnectivity stays as the fallback, and for everything outside a running workout. In the worst case the app works as it does today.

A probe on the phone and watch (2026-10-28, 5.5 minutes) showed mirroring starting within 1 s of the workout and losing none of 64 heartbeats. Lag was 0 to 0.2 s, with a worst case of 5 s.

## What Apple and developers say

| Finding | Source |
|---|---|
| HealthKit launches the phone app in the background to hand it the mirrored session. `workoutSessionMirroringStartHandler` must be set at launch | Apple docs, WWDC23 10023 |
| No background mode or Info.plist key is needed on the phone | Apple docs (none listed) |
| After a disconnect, the watch reconnects by itself while its session runs. The phone's start handler is called again with a new session | Apple docs |
| Mirroring fails on a session that has ended. A new session must call `startMirroringToCompanionDevice` again | Apple docs |
| Data goes both ways | Apple docs, WWDC23 |
| No size limit, ordering, or queuing is documented. A send while disconnected fails | Apple docs (silent) |
| iOS 26.0 to 26.1: mirroring dropped soon after it started. Apple DTS suggested starting mirroring only once the session is running | Developer Forums 804276 |
| No report, good or bad, of mirroring over a multi-hour workout with the screen off | Not found |

The last row is why WatchConnectivity stays as the fallback, and why a real round is part of this plan.

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
- Same rules as `WatchConnectivityTransport`: one send in flight, `maxWaiting` 20, `sendTimeout` 30 s. Exactly one of `reply` or `failure` runs.
- `isConnected` is true once a session is attached and the last send did not fail. It turns false on a send error, on `didDisconnectFromRemoteDeviceWithError`, or when the session ends. Every change calls `delegate.transportReachabilityChanged()`, so the existing reachability code (stream pump, start retry, stream ack) runs on mirroring changes too.
- HealthKit calls the session delegate and send completion on its own queue. Those closures are `@Sendable` and hop to the main actor (see the Swift 6 framework callback rule).
- A test seam, `MirrorChannel` protocol (`send(Data) async throws`, incoming data callback), stands in for `HKWorkoutSession` in tests.

### `RoutingTransport` (Shared)

- Implements `SyncTransport` over a `MirrorTransport` and a `WatchConnectivityTransport`. `SyncService`'s default transport becomes this.
- `send` uses mirroring when `isConnected`. If that send fails with a disconnect (not a timeout), the same payload is sent once over WatchConnectivity. A timeout reports failure as today, since the other side may have received it. Every caller already copes with a repeated message.
- Logs the channel once per change, `Sync channel: mirroring` or `Sync channel: WatchConnectivity`, not per send.
- Forwards both transports' delegate calls to `SyncService`.

### Watch

- `WorkoutManager` calls `startMirroringToCompanionDevice()` when its session reaches `.running` (the DTS advice). That covers a new workout, a recovered one, and each watchdog or forced restart. It hands the session to `MirrorTransport.attach`, and calls `detach` in `sessionFinished`.
- A failed `startMirroringToCompanionDevice` is logged, and mirroring is tried again on the watchdog's next check while the session runs. The round goes on over WatchConnectivity meanwhile.
- If mirroring stays disconnected for 60 s while the session runs, the watch calls `startMirroringToCompanionDevice` again. Apple's docs only describe a reconnect on its own, so the real round checks whether this call is needed or allowed.
- **End of round.** Today the workout stops as soon as the round ends, which also ends mirroring while `EndRound` and the last records are going out. The workout now keeps running after the round ends until the end handshake below is done, or for 60 s at most. The handshake uses the messages that exist now, all over mirroring:

  ```
  Phone ends:   Phone ──EndRequest──▶ Watch ──EndAck(lastSeq)──▶ Phone
  Watch ends:   Watch ──EndRound(lastSeq)──▶ Phone ──EndAck──▶ Watch
  Then:         Watch ──StreamBatch…──▶ Phone ──StreamAck(have)──▶ Watch
                when have > lastSeq, the watch deletes the stream and stops the workout
  ```

  `lastSeq` is the watch's "this is everything" mark, so no new finished message is needed. Sensors and location still stop at once. `activeRoundChanged(false)` stops everything but the workout, and a new `WatchServices` step stops the workout when `StreamSender.onStreamDeleted` fires or the 60 s run out. The 60 s cap covers a phone that is out of range at the end. Then the existing `transferUserInfo` copy of the end, and the stream over WatchConnectivity, finish the job later, as they do today.
- Drill sessions (Putt Data Sharing) run a workout too, so they mirror as well. Nothing uses it there. Their notices and files stay on WatchConnectivity.

### Phone

- `PhoneServices.init` sets `workoutSessionMirroringStartHandler` on the shared `HKHealthStore` before anything else, since HealthKit may launch the app in the background for it. Each call attaches the new session, replacing any old one.
- The phone never ends the mirrored session. The watch ends it.
- `PhoneSync.reachabilityChanged` already resends the start and the stream ack when the watch becomes reachable. With mirroring it runs when the mirrored session arrives, so `startRound` goes out as soon as the workout that `startWatchApp` launched is mirrored. That is about 1 s after the watch launches, while today it waits for WatchConnectivity.

### Size

`SyncCodec.maxMessageBytes` (60 KB) and chunking stay for both channels. A 95.6 KB Broadlands start goes as 2 chunks. The real round checks that a chunk of this size goes over mirroring. If it does not, mirroring gets its own smaller chunk size.

## Steps

1. `MirrorEnvelope` and `MirrorTransport` with the `MirrorChannel` seam. Tests: request and reply, empty reply, timeout, one in flight, disconnect fails waiting sends, reachability change on attach and disconnect.
2. `RoutingTransport`. Tests: mirroring chosen when connected, WatchConnectivity when not, fallback once on a disconnect failure, no fallback on a timeout, `queue`, `updateContext` and `transferFile` always on WatchConnectivity.
3. Watch: start mirroring on `.running`, attach and detach, retry on the watchdog, reconnect after 60 s.
4. Watch: keep the workout running after the round ends until the stream is complete, or 60 s. Tests in `SpotGolfWatchTests` for both endings.
5. Phone: the mirroring start handler in `PhoneServices.init`.
6. Update `SyncTestSupport`'s fake transport so the existing sync flow tests run over `RoutingTransport`, once with mirroring connected and once with it disconnected.
7. Real devices (below).

## Check on real devices

Mirroring does not run on simulators, so these need the iPhone and watch.

| Check | Pass |
|---|---|
| A full round (4 to 5 hours), watch screen off, phone locked in a pocket | The phone's track is never more than about 10 s behind. The log shows the channel and any disconnects |
| Walk out of Bluetooth range for 2 minutes and back | Mirroring reconnects (on its own or by the 60 s retry). The stream catches up |
| A forced workout restart mid-round | Mirroring starts again on the new session |
| Start a round with the phone app not running | HealthKit launches the phone app. The start goes over mirroring |
| End the round on the watch and on the phone | The phone gets the end and every record before the workout stops |
| Battery over the round | No worse than the last rounds over WatchConnectivity |
