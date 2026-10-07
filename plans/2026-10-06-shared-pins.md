# Shared pin locations

Builds on `2026-10-06-pin-location.md`.

## Goal

A pin set by one golfer shows on the map for every other SpotGolf golfer playing the same course that day.

## Service: CloudKit public database

| | |
|---|---|
| Why | Free with the Apple developer account, built into iOS, no server to run, no sign-in screen |
| Container | `iCloud.golf.spot.SpotGolf`, created in the developer portal and added to the phone target in `project.yml` |
| Reading | Works with no iCloud account |
| Writing | Needs the user signed in to iCloud. Without it, pins are still set and synced with the watch, only not shared |
| Permissions | Signed-in users get Write on `Pin` (Security Roles in the CloudKit console), so any golfer can update any hole's pin. By default only a record's creator can change it |
| Who talks to it | The phone only. The watch already sends its pins to the phone |

## Record

Record type `Pin`:

| Field | Type | Notes |
|---|---|---|
| `courseID` | String | `Course.id` from the course data. It is a UUID stored in the course file, so it is the same on every phone |
| `subCourse` | String | The nine's name, for example "Front" |
| `holeNumber` | Int64 | The hole's number on the course, not the round's hole index. Rounds can start on either nine |
| `location` | Location | The pin |
| `courseDate` | String | `yyyy-MM-dd` in the phone's time zone when set. The player is at the course, so this is the course's day |
| `setAt` | Date/Time | When it was set |

- One record per hole per day. Record name: `<courseID>-<subCourse>-<holeNumber>-<courseDate>`.
- Each upload is one save that replaces the record (save policy `.allKeys`), so the last pin saved wins. Two golfers setting the same hole's pin at the same moment is not worth guarding against.
- Indexes: `courseID` and `courseDate` queryable.

## Pins in the round

Every pin lives in `Round.pins`, whatever its source, and syncs between the watch and phone as now.

`PinLocation` gains `source`:

| Source | Set by | Uploaded | Map flag |
|---|---|---|---|
| `center` | The phone at round start, for a hole with no shared pin. At the center of the green | No | Red |
| `shared` | Downloaded from CloudKit | No (it came from there) | Green |
| `set` | The "Set pin location" button on the watch or phone | Yes | Green |

A hole whose course data has no green gets no pin.

### Merging

Replaces "the later `setAt` wins" from `2026-10-06-pin-location.md`. Whether an incoming pin replaces the one on the hole:

| On the hole \ Incoming | `center` | `shared` | `set` |
|---|---|---|---|
| none | Yes | Yes | Yes |
| `center` | No | Yes | Yes |
| `shared` | No | Yes | Yes |
| `set` | No | No | Only from the other device, if its `setAt` is later |

- A `set` pin is never replaced by a downloaded or center pin.
- The player tapping "Set pin location" again replaces their own pin, as now.
- Between the watch and phone, the later `set` pin wins, so both devices keep the same pin.

A `shared` pin outside the hole's green in this phone's course data is dropped before merging. This blocks most bad data.

## Flow

```
Round starts or resumes (phone)
        │
        ▼
Fetch today's shared pins for the course
        │
        ├── hole has a shared pin ──► Round.pins (source shared)
        └── hole has none, or the fetch failed ──► Round.pins (source center)
        │
        ▼
Sync pins with the watch (as now)

Player sets a pin (watch or phone)
        │
        ▼
Round.pins (source set) ──► sync with the other device ──► phone uploads to CloudKit

Display hole moves to the next hole (end of a hole)
        │
        ▼
Phone fetches again and merges into Round.pins ──► sync with the watch
```

### Sharing is decided once per round

When a round starts or resumes, the phone decides whether the round shares pins:

```
Round starts or resumes
        │
        ▼
iCloud account available and "Share Pin Locations" on?
        │
        ├── yes ──► sharing on for this round: download and upload as below
        └── no ───► sharing off for this round: center pins only, no downloads or uploads
```

- The answer holds until the round ends. Signing in to iCloud or changing the switch mid-round takes effect at the next round.
- Nothing is tried again. A failed download or upload is logged, and the round keeps the pins it has. A pin that failed to upload still works on this phone and its watch.

### Upload

- In a sharing round, the phone uploads each `set` pin once it reaches it, from either device. A pin set before the round started sharing, such as before a resume, is never uploaded.

### Download

- In a sharing round, when it starts or resumes.
- In a sharing round, when the display hole moves past the furthest hole shown so far in the round, on either device. The phone sees the change through the display hole sync. Going back to look at an earlier hole and forward again does not fetch.
- One query per fetch: `courseID == X AND courseDate == today`. It returns at most one record per hole.
- The round's hole indexes are matched to records by the nine's name and hole number. `CourseSelection` builds the playing order and these lookups from one list, so they always agree.

## Settings

- New "Share Pin Locations" switch, on by default.
- Off when a round starts: that round neither downloads nor uploads pins.

## Code

| Part | Change |
|---|---|
| `PinLocation` | Gains `source`. The feature is not released yet, so no old data needs reading |
| `Round.mergePins` | The merge rules above. `Round.centerPins()` makes the `center` pins |
| `PinSharing` protocol | `upload(_:course:)`, `fetch(courseID:date:)`. `CloudKitPinSharing` is the real one; tests use a fake |
| `SharedPin` (phone model) | One hole's shared pin. `Round.sharedPin(for:)` and `Round.pins(from:)` convert between a round's hole index and a nine's name and hole number, using `CourseSelection.holeKey(at:)` and `holeIndex(subCourse:number:)` |
| `PhoneSync` | Adds `center` pins when a round starts or resumes (`RoundStore.addCenterPins`) |
| New `PinShareCoordinator` (phone) | Sharing only: decides at round start whether the round shares, fetches at the start and at hole changes (`RoundStore.addSharedPins`), and uploads `set` pins |
| `RoundMapView` | Green flag for `shared` and `set` pins, red for `center` |
| `SettingsStore` / `SettingsView` | The sharing switch |
| `project.yml` | CloudKit capability and container on the phone target |

## Tests

- Unit: every cell of the merge table, center pins only where there is no shared pin and a green exists, outside the green dropped, other days ignored, only `set` pins uploaded, record name, upload skipped when off or with no account, fetch timing. All against the fake.
- Manual: two simulators signed in to different iCloud accounts, same course. Set a pin on one, see it on the other.

## Privacy

- A record holds only the course, hole, pin and time. CloudKit adds an opaque creator ID for the container, which says nothing about who the golfer is.
- The App Store privacy details must list location data shared without being linked to the user.

## Manual setup (not code)

1. Create the `iCloud.golf.spot.SpotGolf` container in the developer portal.
2. After the first upload in development, in the CloudKit console (https://icloud.developer.apple.com):
   - Add the indexes.
   - Give signed-in users Write on `Pin` in Security Roles. Confirm the console allows this before building; if not, go back to one record per golfer.
3. Deploy the schema to production before a release.

## Not in this change

- Showing pins on the watch. It gets every pin through the sync, but shows none today.
- Reporting or removing a bad shared pin. A bad pin stays until someone sets the hole again, or it is deleted in the CloudKit console.
- Two golfers agreeing before a pin shows. One record per hole keeps no history to compare.
