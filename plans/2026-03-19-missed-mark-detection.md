# Missed Mark Guesses

## Summary

Help users who forget to press "At my ball" by providing haptic reminders on the watch and suggesting possible missed mark locations ("Missed Mark Guesses") on the phone. All detection runs on the watch (accelerometer + GPS on the user's wrist) and syncs guesses to the phone for display. The entire feature can be disabled via settings.

## Watch — Haptic Reminder

- Track cumulative distance walked (sum of consecutive breadcrumb distances) and time since last mark
- Detect stationary periods (configurable, default 30 seconds of minimal movement)
- Fire a single haptic when stationary AND no mark within threshold:
  - 50+ yards of cumulative movement since last mark, OR
  - 3+ minutes since last mark
- One reminder per stationary stop — no repeat nagging
- User can ignore with no consequence
- Haptic can be disabled entirely via a setting synced from the phone
- Only runs when Missed Mark Guesses are enabled in settings

## Watch — Guess Detection

All guess detection runs on the watch since it has access to the accelerometer and is always on the user's wrist (phone may be in the cart). Detection only runs when Missed Mark Guesses are enabled in settings.

### Data Collection

- **Breadcrumb trail**: record location every ~5 seconds in a rolling buffer (in-memory). Once a guess is identified from the trail, the breadcrumb points used to identify it can be discarded to free memory.
- **Swing detection**: monitor CoreMotion accelerometer for high-g spikes (~10g+) during active round
  - Golf swings produce distinctive peak acceleration
  - Only need accelerometer, not gyroscope (low battery impact)
  - Hardware already active during workout session

### Guess Logic

A location becomes a "Missed Mark Guess" if either:
- A swing-like accelerometer event was detected there without a mark placed within ~30 seconds
- The user was stationary at that location for the configured threshold (default 30 seconds) without marking

Guesses should be filtered:
- Exclude locations on/near the green (putting doesn't need marking precision)
- Exclude locations near existing marks (already handled)

Guesses are **never expired or auto-removed**. They persist until the user explicitly accepts or deletes them.

### Sync to Phone

When the watch identifies a guess, it sends it to the phone via `SyncService` using the same belt-and-suspenders approach (transferUserInfo + sendMessage). The phone stores guesses alongside the round data.

New `SyncMessage` cases:
- `.addGuess(MissedMarkGuess, UUID)` — guess + round ID
- `.removeGuess(UUID, UUID)` — guess ID + round ID (when user ignores a single guess)
- `.clearGuesses(UUID, Int)` — round ID + hole index (when user clears all guesses for a hole)

## Phone — Display & Interaction

### Missed Mark Guess Display

- Show guesses as ghost pins on the map (visually distinct from real marks — e.g., dashed outline, muted color)
- Label in the UI as "Missed Mark Guesses"
- Never auto-add marks
- Cap at **10 guesses per hole** — detection logic will make bad guesses; this limits clutter

### Guess Interaction

Tapping a ghost pin opens a panel (same presentation style as the existing edit mark sheet). The panel contains:

- **Mark number** — defaults to the best-guess chronological position based on the ghost pin's timestamp relative to existing marks. User can adjust via the same stepper UI used for reordering marks.
- **"My ball was here" button** — converts the guess to a real mark at the selected position. Removes the guess from GuessStore and inserts a mark into the round via RoundStore.
- **"Ignore" button** — deletes the guess (removes it from GuessStore). No mark is added.

### Map Controls

Two buttons alongside the existing location button:

- **Eye icon** (toggle) — shows/hides ghost pins on the map. When ghost pins are hidden, they still exist in GuessStore; this only controls map visibility. Only visible when guesses exist for the current hole.
- **Trash icon** — deletes all guesses for the current hole. Shows a confirmation alert ("Delete all Missed Mark Guesses for this hole?") before proceeding. Only visible when guesses exist for the current hole.

The map UI works regardless of whether Missed Mark Guesses are enabled in settings. If guesses exist (e.g., the setting was enabled during the round but disabled later), they can still be viewed, accepted, ignored, hidden, and deleted.

## Settings

### Phone Settings Screen

Add a settings button on the home page that opens a new settings screen. This is the first settings screen but will house future settings as well.

Initial settings:
- **Missed Mark Guesses** — toggle, default on. Master switch for the entire feature. When disabled:
  - Watch stops collecting breadcrumbs, swing detection, and guess creation
  - Watch stops haptic reminders
  - Stationary threshold setting is hidden
  - Existing guesses remain accessible on the map UI
- **Haptic reminders** — toggle, default on. Enables/disables the haptic nudge on the watch. Only visible when Missed Mark Guesses is enabled.
- **Stationary detection threshold** — picker with 5-second increments from 0 to 120 seconds, default 30 seconds. Controls how long the user must be stationary before the watch considers it a missed mark guess. Only visible when Missed Mark Guesses is enabled.

### Sync to Watch

Settings sync one-way: phone → watch. Uses the same SyncService infrastructure. The watch stores settings locally so it works even if a sync is missed (e.g., phone out of range).

New `SyncMessage` case:
- `.updateSettings(AppSettings)` — sends the full settings object

The watch does **not** have a settings screen. All configuration is done on the phone.

## Architecture

### New Models

- `MissedMarkGuess` — id (UUID), coordinate, timestamp, hole index, reason (swing/stationary), round ID. Codable for persistence.
- `AppSettings` — missedMarkGuessesEnabled (Bool), hapticEnabled (Bool), stationaryThreshold (TimeInterval). Codable for persistence and sync.

### New Services

- `BreadcrumbRecorder` — watch service, records location samples in a rolling buffer. Detects stationary periods. Discards breadcrumbs once a guess is identified from them. Only active when Missed Mark Guesses are enabled.
- `SwingDetector` — watch service, monitors CMMotionManager for high-g accelerometer events. Publishes swing events with the current location. Only active when Missed Mark Guesses are enabled.
- `GuessStore` — shared service (both devices), persists guesses per round. Phone uses it for display; watch uses it to avoid duplicate detection.
- `SettingsStore` — shared service (both devices), persists settings. Phone writes; watch reads. Synced via SyncService.

### New Views

- `SettingsView` — phone only. Settings screen accessible from the home page.

### Integration Points

- `WatchRoundView` — subscribes to BreadcrumbRecorder and SwingDetector, fires haptic when conditions met, creates guesses and sends via SyncService. Checks SettingsStore before doing any work.
- `RoundMapView` — displays ghost pins from GuessStore, handles accept/ignore/hide/delete interactions
- `SyncService` — new message types for guesses, guess removal, guess clearing, and settings
- `RoundStore` — no changes; guesses are stored separately, not mixed into round data

### Persistence

- Guesses: persisted to a JSON file per round (separate from rounds.json) so they survive app restarts. Users may end a round, close the app, and return later to review and fix marks.
- Settings: persisted to a settings JSON file on both devices.
- Breadcrumb trail: in-memory only, discarded as guesses are identified.

## Open Questions

- What's the right accelerometer threshold for swing detection? Needs real-world testing. Start with ~10g and tune.
