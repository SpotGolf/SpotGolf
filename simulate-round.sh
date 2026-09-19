#!/bin/bash
# Simulates a golfer moving through a course by setting simulator GPS locations
# with realistic timing pauses.
#
# Usage: simulate-round.sh <csv-file> [start-row]
#   csv-file:   Path to simulation CSV (latitude,longitude,pause_seconds,description)
#   start-row:  Optional 1-based row to start from (skips earlier rows)

csv=${1:?Usage: simulate-round.sh <csv-file> [start-row]}
start_row=${2:-1}

if [ ! -f "$csv" ]; then
    echo "File not found: $csv"
    exit 1
fi

row=0
while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
    row=$((row + 1))
    [ "$row" -lt "$start_row" ] && continue

    lat=$(echo "$line" | cut -d, -f1)
    lon=$(echo "$line" | cut -d, -f2)
    pause=$(echo "$line" | cut -d, -f3)
    desc=$(echo "$line" | cut -d, -f4-)

    echo "[$row] $desc — ($lat, $lon) — waiting ${pause}s"
    xcrun simctl location "SpotGolf phone" set "$lat,$lon"
    xcrun simctl location "SpotGolf watch" set "$lat,$lon"
    sleep "$pause"
done < "$csv"

echo "Simulation complete."
