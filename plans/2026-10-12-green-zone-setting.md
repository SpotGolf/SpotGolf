# Green zone setting

The green zone, how far from the green's edge still counts as on it, becomes a phone setting and its default drops from 30 m to 10 m. The Broadlands round of 2026-10-12 put 50 of its 85 putt suggestions in stops where no putt was made, many of them off the green: arriving, the bag, the walk off. A tighter zone cuts those, and the setting lets the number be tuned round by round.

What the zone decides, unchanged:

| Where | Use |
|---|---|
| Phone, `StrokeFinder` | Contacts and stops count as putts or chips only inside it |
| Watch, `ContactMonitor` | The mic and device motion run, and Putt Lab records a segment, only inside it |

## Changes

- `HoleShape.chipZoneMargin` is 10 m: the default.
- Phone Settings, Stroke Suggestions section: **Green Zone**, 5 to 50 m in steps of 5, `SettingsKey.greenZone`. The round map passes it to `StrokeFinder.suggestions` as `zoneMargin`, so past rounds follow the setting too.
- `StartRound.greenZone` carries it to the watch (decoded as the default when missing). The watch keeps the last value in `UserDefaults`, like the Putt Lab setting, and sets `ContactMonitor.zoneMargin` when a round becomes active.
- `StrokeFinderRealRoundTests` passes 30 m, the zone its per-hole counts were tuned at.

## Settings reach the watch mid-round

The settings the watch follows (Green Zone, Putt Lab During Rounds, Debug Logging) no longer wait for the next round. `RoundSettingsMessage` carries them: with the round start as before, as its own message each time the round map is opened on the phone, and in the application context, so a watch that was out of reach gets them when it next runs. The watch applies a message for the active round only: the zone changes at once; a change to the Putt Lab setting starts or stops the capture; debug logging switches. Settings for any other round are ignored.
