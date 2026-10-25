# iCloud sync for rounds and settings

The phone saves every ended round and three settings to the player's private CloudKit database, and keeps every phone on the same iCloud account the same. A new or wiped phone gets its rounds back.

## Decisions

| Question | Decision |
|---|---|
| How rounds are stored | `CKSyncEngine`, one record per round, the round and its stream gzipped into one file |
| Across devices | Two-way: rounds added, edited or deleted on one phone show on the others. The newest change to a round wins |
| When a round uploads | When it ends, and again after each later edit. Rounds in progress stay on the phone |
| Round logs | Not uploaded. They stay on the device that recorded them |
| Settings synced | Stroke Suggestions (Stationary Threshold, Green Zone), Clubs (the bag and each club's distance), Pins (Share Pin Locations) |
| Settings not synced | Putt Lab and Log are removed before launch. Debug, map style and iCloud Sync stay on the device |
| Turning it off | A new "iCloud Sync" setting, on by default. See [iCloud Sync setting](#icloud-sync-setting) |
| Which app | The phone only. The watch keeps its own store and gets what it needs from the phone, as today |

SwiftData's own CloudKit sync was ruled out: it would make each of a round's ~8,000 stream entries its own record, and it needs every model's unique IDs removed and every value made optional.

## Size

From the 2026-10-12 Broadlands round, in the app's own record format:

| Part | Gzipped |
|---|---|
| Stream (7,866 fixes and 507 swings, contacts and events), encoded as in [Stream encoding](#stream-encoding) | 42 KB |
| Course selection | 27 KB |
| Holes, strokes, pins, hole starts | ~2 KB |
| **Round record** | **~70 KB**, up to ~130 KB for the longest rounds |

The same stream as the 25-byte records the watch sends is 96 KB gzipped, so the encoding saves about 55 KB per round. 100 rounds a year use about 7–13 MB of the player's iCloud storage. The settings record is under 1 KB.

## CloudKit layout

Container `iCloud.golf.spot.SpotGolf`, the one shared pins use. Shared pins stay in the public database; this is the private database, in a custom zone, since `CKSyncEngine` only syncs custom zones.

| Zone | Record type | Record name | Fields |
|---|---|---|---|
| `Rounds` | `Round` | The round's UUID | `changedAt` (date), `formatVersion` (int), `archive` (asset: the gzipped `RoundArchive`) |
| `Rounds` | `Settings` | `settings` | `changedAt` (date), `formatVersion` (int), `stationaryThreshold` (double), `greenZone` (double), `sharePins` (int), `clubs` (bytes: JSON `[{clubID, distance}]`) |

The round's data is an asset, not a field: a record's fields are limited to 1 MB, assets are not, and only a changed asset is uploaded again.

## RoundArchive

A plain `Codable` struct that holds an ended round and its stream, kept apart from the SwiftData model so the stored format only changes on purpose.

| Value | From |
|---|---|
| `id`, `date`, `endedAt`, `changedAt` | `Round` |
| `holes`, `holeStarts`, `pins`, `displayHole` | `Round` |
| `courseSelection` | `Round.courseSelection.trimmed`: only the nines played and their features, as the watch gets. The course is a fixed ~27 KB of each archive for both Broadlands nines, so a 9-hole round of an 18-hole course saves about 11 KB |
| `stream` | Every `StreamEntry.record` of the round, in index order, encoded as in [Stream encoding](#stream-encoding) |

Left out, because they only matter while the watch records the round: `status` (always `ended`), `resumedFromEnd`, `strokesVersion`, `streamBase`, `logBase`, `lastSeq`, `endConfirmed`. A downloaded round gets `status = .ended`, `endConfirmed = true`, and the rest at their defaults.

Encoded as JSON, with `stream` as base64, then gzipped (the app already gunzips course files). See [Versions](#versions) for how each part says which format it uses.

## Stream encoding

Only the iCloud record uses this. The watch still sends, and both devices still store, the fixed 25-byte `StreamRecord`s: the link resends from any record index and the store truncates by count and time, which a format where each record depends on the one before can't do cheaply.

Each record is the change from the previous record of the same kind, which is small because neighboring records are close in time and place. Nothing is rounded: a decoded stream is byte for byte the stream that was encoded.

```
StreamRecord (25 bytes): kind u8 │ time Int64 ms │ word 1 │ word 2 │ word 3 │ word 4    (words: 32 bits each)
                                          │
                                          ▼  per field: value − same field of the previous record of this kind
                                          ▼  zigzag (−1 → 1, 1 → 2, −2 → 3 …), so small negatives stay small
                                          ▼  varint: 7 bits per byte, high bit set when more bytes follow
encoded record: kind u8 │ Δtime │ Δword 1 │ Δword 2 │ Δword 3 │ Δword 4     (1–2 bytes per field for a fix)
```

| Rule | Detail |
|---|---|
| Fields | Every record's 24 bytes after the kind byte are read the same way: the time as a little-endian `Int64`, then four little-endian 32-bit words taken as `Int32`, with wrapping subtraction. The encoding doesn't need to know what a word holds, so all five kinds come back byte for byte |
| What the words hold | Fix: latitude, longitude, altitude, accuracy, the values that change little. Swing: peak force, then zeros. Contact and gated contact: score, burst, click, turning. Event: code and value, then zeros. A `Float32` word's change is not small, but the 507 swings, contacts and events of a round are a small share of its records, and zeros cost 1 byte each |
| Previous record | Kept per kind byte, so a swing's change is from the last swing, not from the fix before it. The first record of each kind is the change from all zeros |
| Unknown value | `Int32.min`, a fix's "unknown" marker, is encoded as a change like any other value. It costs 5 bytes when it starts and ends, which is rare (no altitude in the first fixes) |
| Order | Records are written in stream index order, so decoding gives back the same indexes |
| Header | A version byte, then a varint record count to check the decode. See [Versions](#versions) |

Measured on the Broadlands round, with only fixes delta-encoded and the other records left at 25 bytes: 204 KB as 25-byte records becomes 65 KB, and 42 KB after gzip. A 1 Hz fix while walking takes about 8 bytes; a still one takes 5 to 6. Encoding the other kinds too can only make it smaller.

## Versions

Each stored format carries its own version, so one part can change without the others. Every version starts at 1.

| Format | Where the version is | Covers |
|---|---|---|
| `Round` record | `formatVersion` field | The record's fields, and which archive format the asset holds |
| `Settings` record | `formatVersion` field | The record's fields, and the `clubs` JSON |
| `RoundArchive` | `version`, a key of the JSON, read on its own before the rest | The archive's keys and what they hold. Kept in the file too, so an archive read without its record (a test, a debug export) still says what it is |
| Encoded stream | The first byte of `stream` | The delta encoding. A change to the 25-byte `StreamRecord` itself is a new stream version |

The record's `formatVersion` lets a phone decide without downloading the asset. What a phone does with each version it reads:

| Version read | Result |
|---|---|
| The one this build writes | Read it |
| An older one this build knows | Read it with that version's decoder, then save the round or settings again in the current format, so old versions leave iCloud over time |
| A newer one | The app needs an update. Leave the record alone and keep the local copy. Never save over it, even with a newer `changedAt`: an older build would lose what the newer format holds. Show the [update notice](#update-notice). The record syncs again once the app is updated |

A newer `Settings` record is an error, not only a skipped record: the phone keeps using its own settings, and stops uploading settings changes, since every save would be refused. Changes made meanwhile stay on the phone and are lost when the update downloads the newer record. A newer `Round` record only skips that round, but shows the same notice, since a newer format anywhere means the app is out of date.

Each version this build has written stays readable in every later build: a decoder is only removed once no version of the app that wrote it is in use.

### Update notice

`CloudSync` keeps `needsAppUpdate`, set when it reads any record with a newer `formatVersion` than this build writes. Each such record is saved in the sync state with its version, since a fetch only returns records changed since the last one. At launch the notice shows again while a saved version is still newer than the build. Once the app is updated, the phone fetches everything again, so it reads those records.

```
fetch reads a record ──▶ formatVersion > this build's? ──no──▶ apply as usual
                                   │
                                  yes
                                   ▼
                  needsAppUpdate = true, record left alone
                                   │
                   ┌───────────────┴────────────────┐
                   ▼                                ▼
     alert, once per launch                 row at the top of Settings,
     (over the round list)                  while needsAppUpdate is set
```

| Part | Text and behavior |
|---|---|
| Alert title | "Update SpotGolf" |
| Alert message | "Your settings or rounds in iCloud were saved by a newer version of SpotGolf. Update the app to keep them in sync on this iPhone." |
| Alert buttons | "Open App Store", which opens the app's App Store page, and "Not Now" |
| Settings row | The same message, with an "Open App Store" button. Stays until the app is updated |
| No App Store link yet | `AppStoreLink.url` is nil until the app is published. Without it the "Open App Store" buttons are left out, and the alert has an "OK" button only |

The alert is never shown during a round in progress: it waits until the round ends, so it never covers the map on the course.

`AppStoreLink.url` is one constant, `https://apps.apple.com/app/id<app id>`, filled in once App Store Connect gives the app its ID. It opens with `openURL`, which hands it to the App Store app.

## Round changes

`Round` gets `changedAt: Date`, set by `RoundStore` on every change made on this phone, and by a download to the downloaded value. `CloudSync` adds a `RoundStore` listener and reacts to the round's status:

```
RoundStore change on this phone
        │
        ├── round in progress ───────────────▶ nothing
        │
        ├── round ended (or edited after) ────▶ CloudSync marks it "save pending"
        │                                         │ (2 s pause, so a burst of edits is one upload)
        │                                         ▼
        │                                     CKSyncEngine asks for the record
        │                                         │
        │                                         ▼
        │                                     build RoundArchive ─▶ gzip ─▶ temp file ─▶ CKAsset
        │
        └── round deleted ───────────────────▶ CloudSync marks it "delete pending"
```

Changes to the stream of an ended round, such as `StreamStore.truncate`, count as an edit of the round: the sync state keeps each round's `changedAt` and record count as last synced, and a difference in either is a save.

## Downloads

`CKSyncEngine` fetches changes on launch, on a push from CloudKit, and when the app comes back to the front.

| Fetched | Local round with that ID | Result |
|---|---|---|
| `Round` record | None | Add the round and its stream |
| `Round` record | Ended, older `changedAt` | Replace the round and its stream |
| `Round` record | Ended, same or newer `changedAt` | Keep the local one. If it is newer, mark it "save pending" |
| `Round` record | In progress | Keep the local one. Can only happen with a reused ID, which UUIDs rule out |
| Deleted `Round` | Ended | Delete the round, its stream and its log |
| `Settings` record | — | Apply it when its `changedAt` is newer than the phone's settings `changedAt` |

A downloaded round never goes to the watch, since only the round in progress does.

When the engine reports a conflict on a save (`serverRecordChanged`), the newer `changedAt` wins: a newer server record is applied as a download, a newer local one is saved again over it.

## Settings

The three settings stay in `UserDefaults` and the bag in `CarriedClub`, so nothing that reads them changes. `CloudSync` watches them:

- `UserDefaults.didChangeNotification` for `stationaryThreshold`, `greenZone` and `sharePins`. Only a value that differs from the last synced one counts as a change.
- A `GolfBagStore` change callback for clubs added, removed or given a new distance.

A change sets `SettingsKey.settingsChangedAt` and marks the `settings` record "save pending". A download writes all four values, then sets `settingsChangedAt` to the record's.

A settings change is timed even while iCloud Sync is off, so it wins when sync is turned on again. The settings the phone has when `CloudSync` first runs are not a change.

The first time a phone syncs with no `settings` record in iCloud, it uploads its own. When the record already exists, the phone takes it, so a new phone gets the player's settings instead of overwriting them with defaults.

## iCloud account

| State | Behavior |
|---|---|
| Signed in | Syncs |
| Not signed in, or iCloud Drive off for SpotGolf | Rounds and settings stay on the phone. No error is shown |
| First fetch fails (no account, no network) | Nothing uploads until a fetch the phone asked for succeeds: `CKSyncEngine` reports a failed fetch as finished too, and a new phone that uploaded before reading iCloud would replace the account's settings with its defaults. The fetch is tried again when the app comes to the front and when the player signs in |
| Signs in | Every ended round and the settings are marked "save pending", then synced as above |
| Signs out, or switches account | The engine's state is reset. Local rounds stay on the phone. Under a new account they upload as if the player had just signed in |

## iCloud Sync setting

A toggle in Settings, `SettingsKey.iCloudSync`, on by default. It stays on this phone and is not synced: turning sync off on one phone must not turn it off on the others.

| Part | Text |
|---|---|
| Section header | "iCloud" |
| Toggle | "iCloud Sync" |
| Footer | "Saves your rounds, clubs and settings to your iCloud account, and keeps them the same on every iPhone signed in to it. Turning it off keeps them on this iPhone only; what is already in iCloud stays there." |

```
on ──turn off──▶ CloudSync stops the engine, keeps its saved state ──▶ off
                 (pending saves and deletes are dropped, nothing local or in iCloud is deleted)

off ──turn on──▶ CloudSync starts the engine, fetches, then marks every ended round
                 and the settings "save pending" ──▶ on
```

| Case | Behavior |
|---|---|
| Off | No fetches, saves or deletes. Rounds and settings are only on the phone. The update notice is not shown |
| Off, then a round is deleted | The round stays in iCloud, and comes back when sync is turned on again. The footer's "what is already in iCloud stays there" covers this |
| Turned on again | Works as signing in: the phone fetches everything, not only changes since its last fetch, so a round deleted while sync was off comes back. The fetch runs first, so the merge rules above decide between the phone's and iCloud's copy of each round, and the `Settings` rules decide the settings |
| On, not signed in to iCloud | The toggle stays on and nothing syncs, as in the table above. The footer adds "Sign in to iCloud in the Settings app to use it." |

## Engine state

`CKSyncEngine` hands back a state to save after each change. `CloudSync` writes it to `Application Support/cloud-sync-state.json` and passes it in at launch. Deleting the file makes the phone fetch everything and upload every ended round again, which the merge rules above make safe.

The file also keeps each record's system fields as iCloud last returned them, so a save edits that copy and is not taken for a conflict.

When the `Rounds` zone is deleted in iCloud, such as when the player deletes SpotGolf's data in iCloud settings, iCloud Sync turns off instead of uploading everything again.

## Code

| File | Change |
|---|---|
| `SpotGolf/Services/CloudSync.swift` | New. The saved state, the pending saves and deletes, and the merge rules |
| `SpotGolf/Services/CloudKitSyncEngine.swift` | New. The `CKSyncEngine` and its delegate, passing events to `CloudSync` |
| `SpotGolf/Models/SyncedSettings.swift` | New. The synced settings, read from and written to `UserDefaults` and the bag |
| `SpotGolf/Models/RoundArchive.swift` | New. The archive struct, building one from a round and its stream, and applying one to the stores |
| `SpotGolf/Models/AppStoreLink.swift` | New. The App Store page's URL, nil until the app is published |
| `SpotGolf/Views/UpdateNotice.swift` | New. The update alert and the Settings row, shown from `CloudSync.needsAppUpdate` |
| `SpotGolf/Views/RoundListView.swift`, `SpotGolf/Views/SettingsView.swift` | Show the alert and the row |
| `SpotGolf/Models/StreamEncoding.swift` | New. Encodes the round's 25-byte records to the delta format and decodes them back, working on the bytes, not on `StreamRecord` values |
| `Shared/Models/Round.swift` | Add `changedAt` |
| `Shared/Services/RoundStore.swift` | Set `changedAt` on each change; a `replace(with:)` for downloads that reports `roundsChanged` only |
| `Shared/Services/StreamStore.swift` | A `replace(_:with:)` that swaps a round's whole stream |
| `Shared/Services/GolfBagStore.swift` | A change callback, and a `replace(with:)` for downloads |
| `SpotGolf/Models/SettingsKey.swift` | Add `settingsChangedAt`, and `iCloudSync` with a default of true |
| `SpotGolf/Views/SettingsView.swift` | The "iCloud" section with the "iCloud Sync" toggle |
| `SpotGolf/PhoneServices.swift` | Make `CloudSync`, and start it when `iCloudSync` is on, outside UI tests. Start and stop it when the toggle changes |
| `project.yml` | `remote-notification` background mode and the `aps-environment` entitlement on the phone, for CloudKit pushes. The iCloud and CloudKit entitlements are already there. The Broadlands export as a test resource |

`CloudSync` talks to the engine through a small protocol, so unit tests can run it with a fake engine and no iCloud account.

## Tests

| Test | Checks |
|---|---|
| `StreamEncodingTests` | Every record of the Broadlands export comes back byte for byte. All five kinds, unknown values, negative changes, the largest and smallest `Int32` and `Int64` values, and an empty stream do too. A wrong record count or a cut-off varint fails |
| `RoundArchiveTests` | A round with strokes, pins, hole starts and a stream comes back the same after build, gzip, gunzip and apply. A newer archive version or stream version is refused, and the local round is kept |
| `CloudSyncTests`, versions | A record with a newer `formatVersion` is not downloaded and is never saved over, even when the local round is newer. It sets `needsAppUpdate`. A newer `Settings` record keeps the phone's settings and stops settings uploads |
| `ICloudSyncUITests` | With `--needs-app-update`, the alert shows once over the round list, and the Settings row shows. With no App Store link, the alert has only "OK". Not covered: the alert waiting for a round to end, since UI tests can't launch mid-round on the phone |
| `CloudSyncTests` (fake engine) | An ended round is saved once after a burst of edits. A round in progress is not saved. A delete is sent. Each row of the downloads table. A conflict keeps the newer round. Settings upload on a new phone with no record, and download when one exists |
| On two real phones on one iCloud account | A round ended on one shows on the other. An edit and a delete carry over. A new club and a changed Green Zone carry over |

UI tests turn sync off: their simulators have no iCloud account, and their rounds must not reach a real one. They still show the toggle, so a UI test checks it is on by default and can be turned off.

| Test | Checks |
|---|---|
| `CloudSyncTests`, setting (fake engine) | Off: an ended round and a settings change send nothing. Turned on again: the fetch runs before the pending saves, and every ended round and the settings are saved |

## Before launch

- Fill in `AppStoreLink.url` with the app's App Store ID, once App Store Connect assigns it.
- Deploy the `Round` and `Settings` record types to the production CloudKit environment from the CloudKit console. Development builds use the development environment until then.
- List the uploaded data in the App Store privacy details as data stored in the player's own iCloud, not collected by the developer.

## Store change

`Round.changedAt` is a new stored value with a default, so SwiftData adds it to stores from earlier builds. Their rounds start with the distant past and take a time on their next change.
