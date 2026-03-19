# Missed Mark Detection

## Summary

Help users who forget to press "At my ball" by providing haptic reminders on the watch and suggesting possible missed mark locations on the phone.

## Watch — Haptic Reminder

- Track time and distance since last mark
- Detect stationary periods (15-30 seconds of minimal movement)
- Fire a single haptic when stationary AND no mark within threshold:
  - 50+ yards of movement since last mark, OR
  - 3+ minutes since last mark
- One reminder per stop — no repeat nagging
- User can ignore with no consequence

## Phone — Missed Mark Suggestions

### Data Collection

- **Breadcrumb trail**: record location every ~5 seconds in a rolling buffer (in-memory, not persisted)
- **Swing detection**: monitor CoreMotion accelerometer for high-g spikes (~10g+) during active round
  - Golf swings produce distinctive peak acceleration
  - Only need accelerometer, not gyroscope (low battery impact)
  - Hardware already active during workout session

### Candidate Logic

A location becomes a "possible missed mark" if either:
- A swing-like accelerometer event was detected there without a mark placed within ~30 seconds
- The user was stationary at that location for 15+ seconds without marking

Candidates should be filtered:
- Exclude locations on/near the green (putting doesn't need marking precision)
- Exclude locations near existing marks (already handled)
- Expire candidates when advancing to the next hole

### UI

- Show candidates as ghost pins on the map (visually distinct from real marks — e.g., dashed outline, muted color)
- Tap a ghost pin to confirm → converts to a real mark
- Dismiss/ignore ghost pins with no consequence
- Never auto-add marks

## Architecture Notes

- `BreadcrumbRecorder` — new shared service, records location samples in a rolling buffer
- `SwingDetector` — new watch service, monitors CMMotionManager for high-g events, publishes swing events with location
- `MissedMarkCandidate` — new model, holds coordinate + timestamp + reason (swing/stationary)
- Haptic logic lives in the watch view layer (WatchRoundView), triggered by breadcrumb/timing analysis
- Candidate display lives in RoundMapView on iOS

## Open Questions

- What's the right accelerometer threshold for swing detection? Needs real-world testing
- Should candidates persist across app restarts or be ephemeral?
- Should the watch show missed mark candidates too, or just the haptic reminder?
- How many candidates should be shown at once? Cap at 3-5?
