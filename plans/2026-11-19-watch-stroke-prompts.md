# Stroke prompts on the watch

Branch: `feat/watch-stroke-prompts`. Phone and watch.

**The design is not finished.** Each part below is marked Confirmed (you said so), Mine (I chose it, you have not confirmed it) or Open (waiting for your answer). Only "Two shown holes" is written as code (step 2). No other code is written until the Open parts are settled.

## Goal

After the watch works out a stroke suggestion, it asks the player to turn it into a stroke, on the watch. For a player whose phone is locked to a push cart.

The stroke must land on the right hole in normal play and in the odd cases, without the player knowing or picking the hole number.

## Status

| Part | Status |
|---|---|
| Suggestions are worked out on the watch; `StrokeFinder` moves to `Shared` | Confirmed |
| Two triggers: a look within 5 m, and walking 15 m away | Confirmed |
| Question on its own pane, Yes and No | Confirmed |
| "Yes" adds the stroke at once, then the club pane | Confirmed |
| "No" only closes the pane | Confirmed |
| A timeout is not an answer and never blocks a later question | Confirmed |
| A new full swing at the spot asks again | Confirmed |
| Putts get the same question, for putt suggestions only | Confirmed |
| Timeout of 10 s, set in the phone's Settings | Confirmed |
| A new message from the watch that adds a stroke | Confirmed |
| The watch and the phone each show their own hole, and neither is sent to the other | Confirmed. Done |
| The watch's arrows set the hole being played | Confirmed. Done |
| The phone's map never follows the watch's hole | Confirmed. Done |
| Question text | Open |
| Putt details (one at a time, putter, no club pane) | Open |
| How the hole of a stroke is decided | Open. A proposal is below |
| A watch pane listing suggestions not yet turned into strokes | Open |
| Whether the phone's map uses the same hole rules | Open |

## Flow

```
full swing in a stop ──▶ the spot is "to ask"
        │
        ├─ player looks at the watch within 5 m of it ───────────┐
        └─ player is 15 m from it ──── wrist tap ────────────────┤
                                                                 ▼
                                                        question pane
                              ┌──────────────────────────┼──────────────────────────┐
                             Yes                         No                    no tap (10 s)
                              │                          │                          │
                 stroke added at once,             pane closes.               pane closes.
                 with the guessed club             Suggestion stays.          Suggestion stays,
                              │                    Asked again only           still "to ask".
                         club pane                 after a newer full
                 (no tap in 10 s keeps             swing at the spot
                  the guess)
```

## Confirmed rules

| | Rule |
|---|---|
| 1 | `StrokeFinder` moves to `Shared`. The watch works out suggestions with the same rules as the phone, so swings at one spot still merge into one suggestion (60 s, 15 m, the strongest wins) |
| 2 | Trigger 1: the player looks at the watch, and a suggestion is within 5 m of where they are |
| 3 | Trigger 2: the player is 15 m from the suggestion. The watch taps the wrist |
| 4 | The question is on its own pane, with Yes and No. Its text never says "swing": that reads as a practice swing |
| 5 | "Yes" adds the stroke at once, with the guessed club. The club pane comes after. Timing out on the club pane keeps the guess |
| 6 | "No" only closes the pane. The suggestion is not deleted and not hidden, on either device. A "No" can be a wrong tap |
| 7 | A timeout is not an answer. It never blocks a later question. Practice swings, a two minute wait, an ignored question, another practice swing and the shot: the player still gets the question on leaving the tee box |
| 8 | A new full swing at the spot asks again, after "No" as well |
| 9 | After a practice swing, looking at the watch shows the full question and the player taps "No". There is no extra button on the normal screen |
| 10 | Putts get the same question, only for a putt suggestion (a contact). Never for a stop suggestion |
| 11 | The timeout is 10 s by default and is set in the phone's Settings |
| 12 | The watch sends an "add this stroke" message. The phone still owns the strokes |
| 13 | The player can always see every suggestion and turn it into a stroke. Today that is the phone's map |
| 14 | Showing the hole number in the question is not a safeguard: the player may not know which hole they are on, and cannot change it there |

## Facts from the code this leans on

| Fact | Where |
|---|---|
| A suggestion's ID comes from a time (the first swing at the spot, or the contact), so it is the same on both devices | `StrokeSuggestion.id(at:)` |
| A suggestion is hidden only while a stroke made from it exists. Deleting the stroke brings it back | `Round.takenSuggestionIDs` |
| The watch keeps the round's whole stream (fixes, swings, contacts, events) until the round has ended and the phone has all of it | `StreamStore`, `StreamSender` |
| The phone owns strokes and sends numbered snapshots. The watch has never added one | `SnapshotSync(sendsStrokes: false)`, `StrokesSnapshot` |
| The watch has no golf bag. Only the phone builds a `GolfBagStore` | `PhoneServices` |
| The watch does not keep hole starts: `applyStrokes` replaces the strokes only | `RoundStore.applyStrokes` |
| The watch already has a prompt of this kind, with a wrist tap that the swing and contact detectors ignore | `RoundEndPrompter`, `SensorInputs.play`, `TapGuard` |
| Today a stroke never changes hole by itself. There is no code that moves one | `RoundStore` |

## When the watch asks

Rows marked Mine fill in details you have not confirmed.

| Event | Effect | Status |
|---|---|---|
| A full swing (10 g or more) | Its spot is "to ask" | Confirmed |
| The screen wakes within 5 m of a "to ask" suggestion | Question, no wrist tap | Confirmed |
| A fix 15 m or more from a "to ask" suggestion | Wrist tap and question | Confirmed |
| Yes | Stroke added. No longer "to ask" | Confirmed |
| No | Not asked again until a newer full swing at the spot | Confirmed |
| Timeout | Still "to ask". Trigger 1 asks at every look | Confirmed |
| Timeout, then trigger 2 | Asks again only after a newer full swing at the spot, or after the player has been back within 5 m of it. Stops GPS drift around the 15 m line from tapping the wrist again and again | Mine |
| "Newer" after an answer | The watch compares the time of the latest full swing at the spot with the time of the answer, not the suggestion's ID: the ID stays the same when a stronger swing replaces a practice swing | Mine |
| The wrist tap was not looked at | The 10 s count only while the screen is awake. A question not looked at within 30 s of the tap is dropped as a timeout, so an old question never shows up at another spot | Mine |
| When `StrokeFinder` runs on the watch | Only when the screen wakes, when a fix is 15 m from the latest full swing, and when a contact arrives. Never on every fix. It runs over the whole round's fixes so IDs match the phone's | Mine |

## Putts

| Rule | Status |
|---|---|
| The same two triggers and the same pane, for a putt suggestion: a contact `StrokeFinder` accepts as a putt | Confirmed |
| No question for a stop suggestion | Confirmed |
| Several putts waiting are asked one at a time, oldest first | Open |
| "Yes" adds the stroke with the putter. No club pane | Open |

Not settled: after a three-putt the player gets three questions in a row on leaving the green.

## Question text (Open)

| Option | Buttons |
|---|---|
| "Count this shot?" and "Count this putt?" (my pick) | Yes, No |
| "Did you hit the ball?" | Yes, No |
| "Add a stroke?" | Yes, No |

## The club pane

| Rule | Status |
|---|---|
| Shown after "Yes" to a shot. The guessed club is marked | Confirmed |
| No tap within the timeout keeps the guess | Confirmed |
| The phone sends the bag (club IDs and yards) to the watch with the round's settings, so the watch can guess and list the clubs with the phone out of reach | Mine |
| The pane lists the bag's clubs without the putter | Mine |
| The guess uses the phone's rule: `ClubGuess`, by the yards to the pin or the green's center | Mine |

## Two shown holes

Done on this branch. Before, both devices showed one hole, sent both ways, with the later change winning.

| | Watch | Phone | Status |
|---|---|---|---|
| Shows | The hole the watch thinks is being played, under the word "Playing" | Any hole | Confirmed |
| Kept in | `Round.playingHoleIndex`, the watch's own | `Round.displayHole`, as before | Confirmed |
| Sent to the other device | Never | Never | Confirmed |
| Arrows or hole circles | Set the hole being played | Show a hole | Confirmed |
| Timer after a pick | None: the player is on the hole they picked | 30 s, as before (`DisplayHole.holdTime`) | Confirmed |
| Moves on by itself | Only when the walk to the next tee brings the player within 15 m of it | As before | Confirmed |

When each hole moves on (`HoleAdvancer`, now in `Shared`, one per device):

| Sign | Watch (playing hole) | Phone (display hole) | Status |
|---|---|---|---|
| Standing on a tee box of the next hole | Moves on | Moves on | As before |
| Left the green (20 fixes on it, then 20 m off it) and 5 m closer to the next tee than 10 s ago | Moves on only within 15 m of that tee | Moves on at once, when that tee is within 100 m of the green | Confirmed |
| The 100 m limit between the green and the next tee | Dropped: within 15 m of the tee the walk is not to the clubhouse | Kept | Mine |
| A hole just picked, with the player within 15 m of the next tee | Stays until the player has been more than 15 m from that tee, or 20 fixes on the green. Without this, "previous" tapped on the next tee is undone by the next fix | No such rule: the 30 s timer | Mine |

Details that are Mine:

| Detail | Choice |
|---|---|
| What moves the phone's hole on, now that the watch does not send its hole | The watch's GPS fixes, as they arrive in the stream (`DisplayHoleAdvance`). The phone is often on a cart, so its own GPS is never on a green or a tee box |
| Fixes that arrive late, after the phone was out of reach | They still move the phone's hole on, in order |
| The phone's 30 s timer | Runs on the phone's clock, so late fixes do not get past it |
| The phone's lock screen activity, Caddie advice and pin sharing | Use the phone's hole, as before |
| A round the watch does not have (a resume after the watch deleted it) | Starts on the first hole on the watch |
| Developer Mode's `displayHole` capture event | Renamed `playingHole` |

Checked against the real rounds in `Data/Simulations` (Broadlands 2026-10-26, Walnut Creek 2026-11-17): the watch's hole reaches every hole, each change 7 to 15 m from the next tee, after the last fix on the green and before the tee box.

How the playing hole relates to the stroke decision below is still Open: the proposal was written before the watch had a playing hole of its own.

## The hole of a stroke (Open: a proposal)

### What cannot be known

At the moment of the swing these two cases look the same to the watch:

| | Approach landed on the next hole's tee box | Green skipped, real tee shot |
|---|---|---|
| Where the player is | Next hole's tee | Next hole's tee |
| Current green reached | No | No |
| Swing | Full swing | Full swing |

No rule on GPS and swings can tell them apart then. Only what the player does later, or the player, can.

### Idea

Holes are played in order and strokes are in time order. So for each stroke there is one thing to decide: **is this the first stroke of a new hole?** The hole is then a count. The player always knows that answer, even when they have forgotten the hole number.

### Evidence

| Strength | Evidence | Status |
|---|---|---|
| Proof | A putt heard in a stop on a green. That green's hole is being played | Proposed |
| Proof | A stroke the player added on the phone. They picked its hole by looking at it | Mine |
| Strong | The player stopped at the current green earlier | Proposed |
| Weak | A full swing at the next hole's tee. The approach case breaks it | Proposed |

### Decision for each full swing

The watch is on hole N.

| | Where the swing is | Hole N so far | Result |
|---|---|---|---|
| 1 | Next hole's tee | Putt heard on N | New hole |
| 2 | Next hole's tee | Stopped at green N earlier, no putt heard | New hole, likely |
| 3 | Next hole's tee | Neither | Unknown. Ask "First shot of a new hole?" |
| 4 | At green N, not at the next tee | Any | Hole N |
| 5 | Anywhere else | Putt heard on N | New hole |
| 6 | Anywhere else | No putt heard | Hole N |

- A putt goes on the hole of the green it was heard on.
- Row 3 is the only case with a second question. It comes after "Yes" and before the club pane.
- Row 3 with no answer: the watch guesses "new hole". The stroke is added at once on the guess and moved if the answer says otherwise.
- "At the tee" is within 10 m of a tee box (`teeShotRadius`). "At the green" is on it or in the green zone.
- The hole shown on the phone plays no part. The watch now has its own playing hole, set by its GPS and its arrows (see "Two shown holes"). How this decision uses it is not settled.

### How it is worked out

Each time the hole is needed, the watch goes through everything it has detected in the round, in time order, starting on the round's first hole:

- full swing suggestions and putt suggestions, answered or not;
- those answered "No" are left out: they are not strokes;
- the answers to the row 3 question.

Nothing else is saved. So ignoring every question on a hole does not leave the watch behind, and later proof changes earlier results.

### Correction

When proof puts the watch on another hole, strokes the watch added move with it:

| Proof says | Strokes that move | Status |
|---|---|---|
| An earlier hole: the watch moved on too soon | Every watch-added stroke since the proof before this one that sits on a later hole goes back to the proven hole | Proposed |
| A later hole: the watch missed a first shot | From the first full swing at the proven hole's tee since the proof before this one. With none, from the first full swing after the player was last at the old hole's green. With neither, nothing moves | Mine (the proposal said "from the stroke hit nearest that hole's tee") |
| Strokes the player added on the phone | Never moved | Mine |

### Cases

| Case | Row | Right at once? |
|---|---|---|
| Normal hole | 1 | Yes |
| Wide shot from another fairway | 6 | Yes |
| Chips back and forth over the green, then putts | 4, 6 | Yes |
| Provisional or re-tee | 6 | Yes |
| Practice swing on the next tee before putting | 3, but "No" to counting it ends it | Yes |
| Tee shot not detected | 5 on the second shot | Yes |
| Tee box missing from the map, putt heard | 5 | Yes |
| Topped tee shot stops beside the previous green | 1, then 6 | Yes |
| **Approach lands on the next tee, shot from there** | 3 | Yes if answered. If not: fixed at the first putt on N |
| **Green skipped, then the tee shot** | 3 | Yes, answered or not |
| No putt heard on N, or a chip-in from the fringe | 2 | Yes |
| Next tee within 10 m of green N, chip from there, no putt yet | 3 | Yes if answered |
| Bladed chip from the fringe onto the next tee, shot back | 2 | No. Fixed at the first putt on N |
| Putt rolls far off the green, chip back | 5 | No. Fixed at the next putt on N |
| Tee box missing from the map, and no putt heard on N | 6 | No. Fixed at the first putt on N+1 |
| A hole skipped (4, then 6) | 5 | No. Fixed at the first putt on 6 |

### What stays wrong

| | Case |
|---|---|
| 1 | The microphone fails: no putt is heard, so nothing is corrected. Rows 2, 3, 4 and 6 still decide |
| 2 | Approach lands on the next tee, the shot from there is holed, then the tee shot from the same tee, all unanswered |
| 3 | The player answers the row 3 question wrong and no putt is heard afterwards |
| 4 | Two holes share one green: the putt proves either, so the watch keeps the hole it is on |
| 5 | A wrong "No" on a tee shot, with no putt heard on the hole before: the next shots stay on the old hole until a putt is heard |

The fix by hand for all of these is on the phone: delete the stroke, the suggestion comes back, show the right hole, and accept it there.

### Earlier ideas, dropped

| Idea | Why |
|---|---|
| A question covers every swing since the last answer | "No" does not delete anything, and the last answer may be two holes back |
| "No" hides the suggestion on the phone | A "No" can be a wrong tap |
| After no answer, trigger 2 never asks again | It must not block the question after later swings |
| A small "Swing? Yes" button on the normal screen for trigger 1 | No new button on the normal screen |
| One "2 putts?" count on leaving the green | Putts get the same question as shots |
| Naming the hole in the question | The player may not know the hole and cannot change it there |
| Tee and green rules A, B, C1 and C2 | Rule B breaks when the green is skipped: the next tee shot looks like a shot back to the green |

## Sync

The phone stays the owner of strokes. The watch sends changes; the phone applies them and sends its snapshot back. All of this section is Mine, apart from "a new add message is fine".

| Message | Direction | Holds |
|---|---|---|
| Add a stroke | Watch → phone, queued | The stroke (its ID, place, hit time, club, the suggestion's ID) and the hole |
| Set a stroke's club | Watch → phone, queued | Stroke ID, club ID |
| Move strokes to a hole | Watch → phone, queued | Stroke IDs, the hole. Only if the hole proposal is accepted |
| Round settings | Phone → watch, as today | Adds the timeout and the bag. `StartRound` gets the same two |
| Strokes snapshot | Phone → watch, as today | Adds the number of the last watch change the phone has applied |
| The watch's hole | Not sent (Confirmed). `DisplayHoleMessage` is deleted | |

- Each watch change carries a number, counted up per round.
- The watch applies its own change to its copy of the round at once, so the stroke count is right and the suggestion is hidden.
- The watch keeps its changes until a snapshot says the phone has applied them, and puts them back on top of any snapshot that came before that. They are saved, so a relaunch keeps them.
- Queued messages are delivered when the phone is next in reach, as stream records are.
- A stroke the player deletes on the phone stays deleted: the watch's change was already counted as applied.
- On the phone, an added stroke starts its hole in the timeline, as a stroke from a suggestion does today.

## Settings

| Setting | Where | Values | Status |
|---|---|---|---|
| Watch question timeout | Phone Settings, "Stroke Suggestions" section | 5, 10, 15, 20, 30 s. Default 10 | Confirmed (the values are Mine) |

Saved and sent like Green Zone: `SettingsKey`, `SyncedSettings`, `RoundSettingsMessage`, `StartRound`, and kept on the watch for a round resumed after a relaunch. It covers the question pane, the row 3 question and the club pane.

## Code

| File | Change |
|---|---|
| `SpotGolf/Services/StrokeFinder.swift` → `Shared/Services/StrokeFinder.swift` | Moved. No change to its rules |
| `SpotGolf/Utilities/HoleOverview.swift`, `Shared/Utilities/ClubGuess.swift` | The club guess for a stroke on a hole moves to `Shared`, so the watch uses the same one |
| `Shared/Services/HoleAssigner.swift` (new) | The hole decision: detected shots and putts, answers and the course in; a hole for each out. No saved state. Only if the proposal is accepted |
| `Shared/Models/SyncMessage.swift` | The three new messages; the timeout and bag in `RoundSettingsMessage` and `StartRound`; the applied number in `StrokesSnapshot` |
| `Shared/Services/RoundStore.swift` | Moving strokes to another hole, in time order, with both holes' starts following |
| `SpotGolf/Sync/PhoneSync.swift` | Applies the watch's changes; sends the timeout and the bag |
| `SpotGolf/Models/SettingsKey.swift`, `SpotGolf/Models/SyncedSettings.swift`, `SpotGolf/Views/SettingsView.swift` | The timeout setting |
| `Shared/Models/Round.swift`, `Shared/Models/DisplayHole.swift`, `Shared/Services/RoundStore.swift` | Done. `playingHoleIndex` for the watch. `displayHole` and its hold stay, for the phone. The merge and the `displayHoleChanged` event are deleted |
| `Shared/Models/SyncMessage.swift`, `Shared/Services/Sync/SnapshotSync.swift`, `SpotGolf/Sync/PhoneSync.swift`, `SpotGolfWatch/Sync/WatchSync.swift` | Done. `DisplayHoleMessage` is deleted, and the hole is taken out of `StartRound` and `SyncContext` |
| `SpotGolfWatch/Services/HoleAdvancer.swift`, `GreenExit.swift` → `Shared/Services/` | Done. Moved, with one rule for the playing hole and one for the display hole |
| `SpotGolf/Services/DisplayHoleAdvance.swift` (new), `SpotGolf/Sync/StreamReceiver.swift` | Done. The phone moves its own hole on from the stream's fixes |
| `SpotGolfWatch/WatchServices.swift`, `SpotGolfWatch/Views/WatchRoundView.swift` | Done. The watch moves and shows the playing hole, under "Playing" |
| `SpotGolf/Services/RoundTracker.swift`, `SpotGolf/Utilities/ClubAdvice.swift`, `SpotGolf/Services/PinShareCoordinator.swift`, `SpotGolf/Views/RoundMap/` | No change: they read the phone's hole |
| `SpotGolfWatch/Services/StrokePrompter.swift` (new) | Which suggestions are "to ask", the two triggers, the answers and the timeout. Plain logic like `RoundEndPrompter`, no views |
| `SpotGolfWatch/WatchServices.swift` | Feeds swings, contacts, fixes and screen wakes to the prompter; plays the wrist tap through `sensors.play`; runs the timeout |
| `SpotGolfWatch/Sync/WatchSync.swift` | Sends the watch's changes, keeps them until applied, puts them back over snapshots, stores the timeout and the bag |
| `SpotGolfWatch/Views/StrokePromptView.swift` (new), `SpotGolfWatch/Views/WatchRoundView.swift` | The question pane, the row 3 question and the club pane, covering the round's pages like the end round prompt. Buttons call `sensors.tapped()` |
| `SpotGolfWatch/SpotGolfWatchApp.swift` | Tells the prompter when the screen wakes (`scenePhase` active) |
| String catalogs | The new text |
| `project.yml` | No change. Run `xcodegen generate` for the moved and new files |

## Tests

Every case is tested with made-up courses and tracks (`PathCourse`). Real rounds are normal play, so they are only a check that normal play still works, not proof for the odd cases.

| Tests | Cover |
|---|---|
| `StrokeFinderSuggestionTests`, `StrokeFinderRealRoundTests` | Pass unchanged after the move |
| `StrokePrompterTests` (new, watch) | Each row of "When the watch asks" and of "Putts" |
| `HoleAssignerTests` (new) | Each row of "Cases", "Correction" and "What stays wrong" |
| Sync tests (phone tests, both sides) | Add, set club, move; phone out of reach, then delivered; a snapshot that came before the phone applied a change; a stroke deleted on the phone stays deleted |
| `RoundStoreTests` | Moving strokes between holes, and the hole starts after it |
| Settings tests | The timeout is saved, synced and sent to the watch |
| `RoundTests`, `RoundStoreTests`, `SyncFlowTests`, `DisplayHoleAdvanceTests`, `HoleAdvancerTests`, `HoleAdvancerRealRoundTests` | Done, for two shown holes: a pick on either device does not reach the other, the watch's fixes move the phone's hole on, the phone's hold stays, and the watch's 15 m rule and picked holes |
| Watch UI test | The question pane, Yes, the club pane and its timeout |
| Replay of a real round on this session's simulator pair (`Scripts/replay-round.py`) | The whole flow, by hand |

## Known weak points

| Case | What happens |
|---|---|
| A duff hit again from the same spot within 60 s | One suggestion (today's rule), so one question and one stroke. The other is added on the phone |
| Stepping 15 m back from the tee to wait | A question the player ignores or answers "No". They are asked again after the shot |
| Walking 15 m to the cart for another club | The same |
| A soft pitch under 10 g | No suggestion, so no question, as on the phone today |
| Three putts | Three questions in a row on leaving the green |
| Whether the watch sees the screen wake during a workout | Must be checked on a real watch; the simulator does not show it |
| `StrokeFinder` over a whole round on the watch | Its run time must be measured on a real watch. If it is too slow, it runs over the fixes since the hole before |

## Open questions

1. Is the extra question in row 3 acceptable? It is the only case that asks it.
2. Is "new hole" the right guess when row 3 is not answered?
3. Are you fine with strokes moving to another hole when a putt proves the watch wrong?
4. Does the watch need a pane listing the suggestions not yet turned into strokes, for after a wrong "No"?
5. Should the phone's map use the same hole rules, or keep today's, where the player picks the hole by looking at it?
6. Question text: "Count this shot?" and "Count this putt?"?
7. Putts: asked one at a time, with the putter and no club pane?
8. Answered: the watch's arrows set the hole being played. See "Two shown holes".
9. Answered: the phone's map never follows the watch's hole. Nothing is sent. See "Two shown holes".

## Steps, once the Open parts are settled

1. Move `StrokeFinder` and the club guess to `Shared`. Run their tests.
2. Done. Two shown holes: neither hole is sent, the watch has its own playing hole, and the phone keeps its hold.
3. `HoleAssigner` with its tests.
4. `StrokePrompter` with its tests.
5. The new messages, the watch's kept changes and the phone's side, with the sync tests.
6. Moving strokes between holes in `RoundStore`, with tests.
7. The timeout setting and sending it and the bag to the watch.
8. The watch panes and the wiring in `WatchServices`, with the watch UI test.
9. Replay a round on this session's simulator pair.
10. Check screen wake and `StrokeFinder`'s run time on a real watch.

## Not in this change

- Adding a stroke by hand on the watch, with no suggestion.
- Deleting a stroke on the watch.
- Penalty strokes and shot quality on the watch.
