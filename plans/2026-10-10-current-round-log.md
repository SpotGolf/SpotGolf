# Current round log

Open the log of a round that is starting, active, or ending, so a problem can be read mid-round instead of after the round ends.

## Before

The Log swipe action existed only in Past Rounds, and a starting round's lines were filed under the round, so they could not be read anywhere in the app until the round ended.

## Changes

| Where | Change |
|---|---|
| Round list, Active Round row | Swipe right offers Log, the same sheet Past Rounds open |
| Map, edit mode | A Log button below Hole times in the right-hand button column opens the same sheet |
| `LogSheet` | `LogView` in a navigation stack with Done, shared by the list and the map |

The log view already reloads as lines arrive, so the sheet shows new lines while it is open.

## Tests

`LogUITests`: the active round's log opens from its row and from the map, shows the round's start line, and closes with Done.
