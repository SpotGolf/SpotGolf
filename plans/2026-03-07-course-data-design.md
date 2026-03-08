# Course Data Integration Design

## Overview

Integrate course data from the SpotGolf/CourseData GitHub repository into SpotGolf. Users can search for or find nearby courses when starting a round. Course data provides per-hole distance information to greens and features, and enables auto-advancing holes via GPS.

Course selection is optional. Users can always start a round without course data.

## Data Sources

### Index File

A single `index.json` in the CourseData repo listing all courses. Versioned via a separate `index.version` file containing an incremental integer.

**Index entry format:**
```json
{
  "name": "Broadlands Golf Course",
  "coordinate": { "latitude": 39.956543, "longitude": -105.040375 },
  "holes": 18,
  "path": "US/CO/Broomfield/Broadlands-Golf-Course.json"
}
```

City, state, and country are derived from the path (e.g., `US/CO/Broomfield/...`).

### Course JSON

Full course data fetched from GitHub raw URL by path. Contains sub-courses, holes, tees, greens (front/middle/back), features (bunkers, water with front/back coordinates), par, yardages, and handicaps.

## Caching

- **Index**: Cached locally. On course selection screen open, fetch `index.version`. If newer than cached version, re-download `index.json`. Fall back to cached index if offline.
- **Course JSON**: GZIP-compressed local cache with 5MB cap. Always re-download when online. Use cache only when offline.

## Course Selection Flow (iOS Only)

1. User taps "New Round" - course selection screen appears.
2. Nearby courses shown automatically (within 10 miles, sorted by distance).
3. Search bar at top for searching by name.
4. Each result shows: course name, city/state, distance from user.
5. User taps a course:
   - If multiple sub-courses, prompted to pick 1 or 2 sub-courses and their order.
   - Defaults to "Front" then "Back" if those exist.
   - User can select just 1 sub-course for a 9-hole round.
6. User can skip course selection entirely to start without course data.
7. Course JSON downloaded and attached to the round.

## Distance Display

### iOS (Map View)

A card/panel on the map view showing distances, visible at all times when course data is attached. Updates live as the user moves:
- Distance to front/middle/back of green.
- Distances to features (bunkers, water) that are ahead of the player, sorted by distance from the ball.

### watchOS

After "At my ball", the "Swing away" screen appears and stays until the user taps a **Dismiss** button (no timer). It shows:
- "Swing away" message.
- Distance to front/middle/back of green.
- Distances to features ahead of the player.

## Auto-Advance Holes

When course data is attached, the app detects proximity to tee boxes and auto-advances to the correct hole based on the selected sub-course order.

**Manual override**: When the user manually navigates to a different hole (prev/next), auto-advance pauses. A "Resume round" button appears that returns to the auto-detected hole and re-enables auto-advance.

## Sync

Course data (selected course + sub-courses) syncs from iOS to watchOS via the existing SyncService. The watch never selects a course - it only receives course data from the phone.

## Key Decisions

- Course selection is optional - the CourseData repo is new and may not have all courses.
- Nearby radius: 10 miles.
- Only features ahead of the player are shown (between ball and green).
- watchOS "Swing away" uses dismiss button instead of a timer.
- iOS distance panel is always visible (not just after "At my ball").
- Auto-advance pauses on manual hole navigation; "Resume round" button re-enables it.
