# Hole advance improvements

Here are some cases:

* "Ideal"
  1. Player is on hole 1
     * `currentDisplayHole = 1 && holeTimeline[0] = now`
  2. Stands on teebox
  3. Hits tee shot
  4. Traverses down the hole (generally in the direction of the centerline)
  5. Hits second shot
  6. Traverses to the green
     *  `if (GPS fix on hole 1 green) displayLock = false`
  7. Putts a few times
  8. Leaves green and heads to hole 2 
     * `if (10m from teebox && !displayLock) currentDisplayHole = 2`
* "Retires from hole"
  1. Player is on hole 1
     * `currentDisplayHole = 1 && holeTimeline[0] = now`
  2. Stands on teebox
  3. Hits tee shot
  4. Traverses down the hole (generally in the direction of the centerline)
  5. Hits second shot
  6. Traverses toward green
  7. Hits another shot
  8. Keeps traversing
  9. Hits many more shots
  10. Never goes to the green and instead walks to hole 2 without finishing hole 1 
      * `if (10m from teebox) currentDisplayHole = 2`
* "Parallel holes"
  1. Player is on hole 1
     * `currentDisplayHole = 1 && holeTimeline[0] = now`
  2. Stands on teebox
  3. Hits tee shot
  4. Traverses down the hole on to hole 2's fairway
     * `if (10m from teebox && !displayLock) currentDisplayHole = 2 else no change`
  5. Hits second shot
  6. Traverses toward green and returns to hole 1
  7. Hits another shot
  8. Traverses to the green
     *  `if (GPS fix on hole 1 green) displayLock = false`
  9. Putts a few times
  10. Leaves green and heads to hole 2
      * `if (10m from teebox && !displayLock) currentDisplayHole = 2`
* "Shot from Teebox"
  1. Player is on hole 1
     * `currentDisplayHole = 1 && holeTimeline[0] = now`
  2. Stands on teebox
  3. Hits tee shot
  4. Traverses down the hole (generally in the direction of the centerline)
  5. Hits second shot
  6. Traverses toward green
  7. Hits another shot which lands on hole 2's teebox
  8. Traverses to his ball and hits it back to hole 1
     * `currentDisplayHole = 2`
     * `if (user manually changes to hole 1) currentDisplayHole = 1 && displayLock = true else displayLock not changed`
  9. Walks back to hole 1 and hits his ball on the green
     *  `if (GPS fix on hole 1 green) displayLock = false`
  10. Putts a few times
  11. Leaves green and heads to hole 2
      * `if (10m from teebox && !displayLock) currentDisplayHole = 2`
* "Reverse shot"
  1. Player is on hole 1
     * `currentDisplayHole = 1 && holeTimeline[0] = now`
  2. Stands on teebox
  3. Hits tee shot
  4. Traverses down the hole (generally in the direction of the centerline)
  5. Hits second shot, which hits a tree and lands behind him
  6. Traverses backwards to his ball
  7. Hits another shot
  8. Traverses to the green
  9. Putts a few times
  10. Leaves green and heads to hole 2
      * `if (10m from teebox && !displayLock) currentDisplayHole = 2`
* "Official OB rule"
  1. Player is on hole 1
     * `currentDisplayHole = 1 && holeTimeline[0] = now`
  2. Stands on teebox
  3. Hits tee shot
  4. Traverses down the hole (generally in the direction of the centerline)
  5. They realize their tee shot went out of bounds and they didn't hit a provisional ball
  6. Traverses backwards to the teebox
     * `if (10m from teebox && !displayLock) currentDisplayHole = 1`
  7. Hits another tee shot
  8. Traverses down the hole (generally in the direction of the centerline) towards their ball that is now inbounds
  9. Hits another shot
  10. Traverse to the green
      * `if (GPS fix on hole 1 green) displayLock = false`
  11. Putts a few times
  12. Leaves green and heads to hole 2
      * `if (10m from teebox && !displayLock) currentDisplayHole = 2`
* "Walks through teebox"
  1. Player is on hole 1
     * `currentDisplayHole = 1 && holeTimeline[0] = now`
  2. Stands on teebox
  3. Hits tee shot
  4. Traverses down the hole
  5. Hits second shot
  6. Traverses toward green but walks through hole 2's teebox
     * `if (10m from teebox && !displayLock) currentDisplayHole = 2`
     * `if (user manually changes to hole 1) currentDisplayHole = 1 && displayLock = true else displayLock not changed`
  7. Hits another shot
  8. Traverses to the green
     * `if (GPS fix on hole 1 green) displayLock = false`
  9. Putts a few times
  10. Leaves green and heads to hole 2
      * `if (10m from teebox && !displayLock) currentDisplayHole = 2`
* "Walks through green"
  1. Player is on hole 1
      * `currentDisplayHole = 1 && holeTimeline[0] = now`
  2. Stands on teebox
  3. Hits tee shot
  4. Traverses down the hole
  5. Hits second shot
  6. Traverses toward green but walks through hole 2's green
     * No change to `displayLock` here because `currentDisplayHole != hole of the GPS fix inside green`
  7. Hits another shot
  8. Traverses to the green
     * `if (GPS fix on hole 1 green) displayLock = false`
  9. Putts a few times
  10. Leaves green and heads to hole 2
      * `if (10m from teebox && !displayLock) currentDisplayHole = 2`
* "Skip"
  1. Player is on hole 1
      * `currentDisplayHole = 1 && holeTimeline[0] = now`
  2. Player is finishing hole 1 and the marshall tells him to skip hole 2
  3. He walks past or through hole 2's teebox, along the hole, past hole 2's green to hole 2
     * `if (10m from teebox && !displayLock) currentDisplayHole = 2`
     * `if (GPS fix on hole 2 green) displayLock = false`
  4. He'll now play hole 3 without playing hole 2 at all
     * `if (10m from teebox && !displayLock) currentDisplayHole = 3`

Does this work?

* Separate the UI display from the hole timeline. A hole can be displayed as the active hole, but until the first stroke suggestion on a hole is converted to a stroke by the player, the timeline is not updated.
* There is a "Current display hole" variable that is used solely for displaying distances on the watch and phone. This is separate from the Hole Timeline.
* The display is updated when the player's proximity to a Hole's teebox is less than 10m for more than 10 GPS fixes and they aren't on the green of any hole.
* The user can easily change the "Current display hole" with the arrows on the watch and the numbered hole buttons on the phone. No need to click "Play this hole" since it is for display purposes only.
* This fixes any issues where the player is on a hole but the display incorrectly changes the "Current display hole"
* Once the user changes the "Current display hole", the "Display lock" is enabled and keeps the display on that hole until the player has GPS fixes in that hole's green. Then the "Current display hole" can be updated using the distance calculation again. However, anytime the player changes the hole manually on the watch or phone, the "Display lock" is cleared and the "Current Display hole" is updated.
* The Hole Timeline is updated based on "Stroke conversions". These occur when a player converts a "Stroke suggestion" to a "Stroke" or when they manually add a "Stroke" to a hole in the UI. Converting a "Stroke suggestion" has a timestamp that is used to update the timeline (if this is the first stroke on a hole). If they player manually adds a Stroke, then the timestamp of that stroke is calculated using the closest GPS fix to the location.
