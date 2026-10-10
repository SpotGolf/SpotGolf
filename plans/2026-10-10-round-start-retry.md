# Round start retry

Fix for rounds that fail to start with "The watch did not respond" while the watch is next to the phone.

## What the log showed

A round log from 2026-10-10 (`Downloads/round-log.txt`):

| Time | Event |
|---|---|
| 03:36.9 | Phone sends the start, fails at once: unreachable |
| 03:37.3 | Watch launched by the phone, workout running |
| 03:42, 03:47 | Phone retries every 5 s, both unreachable |
| 03:51.9 | 15 s timer fires, phone shows "did not respond" |
| 03:53.3 | Phone sees the watch as reachable. Nothing sent: the state is timed out |
| 04:39 | Watch stops its workout, no round arrived in 60 s |
| 04:58 | Retry tapped, watch relaunched, round confirmed in 1.5 s |

- The phone takes a long time to see a watch app it launched as reachable, longer than the 15 s start timeout.
- After the timeout the phone stopped sending, so the reachable window at 03:53 was wasted.
- The watch gave up its workout after 60 s, after which it is reachable only while on screen.

## Changes

| # | Change | Where |
|---|---|---|
| 1 | Resend the start on every reachability change while the round is starting, waiting or timed out. Refusals still wait for the user | `PhoneSync.reachabilityChanged` |
| 2 | Keep the 5 s resend running after the 15 s timer, until the watch confirms or the user cancels. Cancel stops the resend timer | `PhoneSync.retryLater`, `stopWaiting` |
| 3 | The watch also sends its confirmation as its own message, not only as the reply, so a lost reply is covered | `WatchSync.startRound` |
| 4 | The watch's workout waits 3 minutes for a round instead of 60 s, and each launch moves the deadline | `WatchServices.startWorkoutWaitingForRound` |
| 5 | The timed-out banner says the phone is still trying and shows progress. Retry and Cancel stay | `RoundSyncBanner` |

## Tests

`SyncFlowTests`:

- Timed out, then reachable: the round goes active with no Retry.
- Timed out with sends failing: the retry timer keeps sending and the round goes active once sends work.
- Retry after timeout relaunches the watch app.
- Cancel after timeout stops the resends.
- Lost reply: the watch's own confirmation activates the round.

## Device test

On the physical pair, wrist down with the watch app not on screen: start a round from the phone, do not touch the watch, and confirm the round goes active within a minute. Export the round log.
