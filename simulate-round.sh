#!/bin/bash
# Replays a round exported from SpotGolf by setting the simulator GPS location for each
# track row, at the same pace the fixes were recorded.
#
# Usage: simulate-round.sh <csv-file> [first-line] [last-line]
#   csv-file:    Round export (header: type,timestamp,latitude,longitude,...,peakG)
#   first-line:  Optional file line number to start from (the header is line 1)
#   last-line:   Optional file line number to stop after (defaults to the end of the file)
#
# Only track rows are replayed. Swing and mark rows are skipped because the app creates them.
# Each fix is sent at (start time + its offset from the first replayed fix), so the timing
# does not drift over a long replay. If sending falls behind, fixes are sent right away until
# the replay catches up.

usage="Usage: simulate-round.sh <csv-file> [first-line] [last-line]"
csv=${1:?$usage}
first_line=${2:-2}
last_line=${3:-0}

if [ ! -f "$csv" ]; then
    echo "File not found: $csv"
    exit 1
fi

if ! [[ "$first_line" =~ ^[0-9]+$ && "$last_line" =~ ^[0-9]+$ ]]; then
    echo "$usage"
    exit 1
fi

if [ "$last_line" -ne 0 ] && [ "$last_line" -lt "$first_line" ]; then
    echo "last-line ($last_line) is before first-line ($first_line)"
    exit 1
fi

header=$(head -1 "$csv" | tr -d '\r')
expected="type,timestamp,latitude,longitude,altitude,horizontalAccuracy,source,hole,stroke,markType,peakG"
if [ "$header" != "$expected" ]; then
    echo "Unexpected header in $csv"
    echo "  found:    $header"
    echo "  expected: $expected"
    exit 1
fi

# Prints "<line> <offset-seconds> <latitude> <longitude> <timestamp>" for each track row in range.
# Offsets are seconds since the first track row in range. Timestamps look like
# 2026-09-22T20:24:39.387Z and are converted to epoch seconds without calling date.
points=$(awk -F, -v first="$first_line" -v last="$last_line" '
    function days_from_civil(y, m, d,    era, yoe, doy, doe) {
        y -= (m <= 2)
        era = int((y >= 0 ? y : y - 399) / 400)
        yoe = y - era * 400
        doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
        doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
        return era * 146097 + doe - 719468
    }
    function epoch(ts,    secs) {
        secs = substr(ts, 18)
        sub(/Z$/, "", secs)
        return days_from_civil(substr(ts, 1, 4) + 0, substr(ts, 6, 2) + 0, substr(ts, 9, 2) + 0) * 86400 \
            + substr(ts, 12, 2) * 3600 + substr(ts, 15, 2) * 60 + secs
    }
    { sub(/\r$/, "") }
    NR < first || (last > 0 && NR > last) || $1 != "track" { next }
    {
        t = epoch($2)
        if (!started) { start = t; started = 1 }
        printf "%d %.3f %s %s %s\n", NR, t - start, $3, $4, $2
    }
' "$csv")

if [ -z "$points" ]; then
    echo "No track rows in lines $first_line-${last_line/#0/end}."
    exit 1
fi

count=$(echo "$points" | wc -l | tr -d ' ')
duration=$(echo "$points" | tail -1 | cut -d' ' -f2)
echo "Replaying $count fixes over $(awk -v s="$duration" 'BEGIN { printf "%dh %02dm %02ds", s / 3600, (s % 3600) / 60, s % 60 }')"

# Wall-clock start in epoch seconds with sub-second precision. /bin/bash 3.2 has no
# EPOCHREALTIME, so perl does the timing.
start_wall=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')

while read -r line offset lat lon ts; do
    # Sleep until this fix is due, then print how late it is (0 when on time).
    late=$(perl -MTime::HiRes=time,sleep -e '
        my $due = $ARGV[0] + $ARGV[1];
        my $wait = $due - time;
        sleep($wait) if $wait > 0;
        printf "%.1f", time - $due;
    ' "$start_wall" "$offset")

    echo "[line $line] $ts +${offset}s ($lat, $lon) late ${late}s"
    xcrun simctl location "SpotGolf Phone" set "$lat,$lon" &
    xcrun simctl location "SpotGolf Watch" set "$lat,$lon" &
    wait
done <<< "$points"

echo "Simulation complete."
