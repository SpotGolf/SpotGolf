#!/bin/bash
row=${1:?Usage: update-location.sh <row-number>}
line=$(sed -n "${row}p" "$(dirname "$0")/TestFixtures/test-locations.csv")
if [ -z "$line" ]; then
    echo "Row $row not found"
    exit 1
fi
lat=$(echo "$line" | cut -d, -f1)
lon=$(echo "$line" | cut -d, -f2)
hole=$(echo "$line" | cut -d, -f3)
echo "Setting location to $lat,$lon (hole $hole)"
xcrun simctl location "SpotGolf phone" set "$lat,$lon"
xcrun simctl location "SpotGolf watch" set "$lat,$lon"
