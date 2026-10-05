#!/bin/bash
# Puts a round in the phone simulator into the state of a live round where no strokes have been
# added yet: the hole timeline keeps only its first entry (the round start), every hole's strokes
# are removed, and the round's hidden suggestions are forgotten. The GPS track and swings are
# kept, so every suggestion shows again. Use it after importing a round export to see what the
# app does for holes with no start yet.
#
# Usage: reset-timeline.sh [round-id]
#   round-id:  The round to reset. Defaults to the one active round.
#
# The watch simulator's copy of the round, if it has one, is reset the same way so a sync can't
# bring the entries back. Both apps are closed first and the phone app is relaunched. The
# previous rounds.json is kept next to it as rounds.json.<time>.bak.

set -euo pipefail

phone="SpotGolf Phone"
watch="SpotGolf Watch"
round_id=${1:-}

phone_dir=$(xcrun simctl get_app_container "$phone" golf.spot.SpotGolf data)
watch_dir=$(xcrun simctl get_app_container "$watch" golf.spot.SpotGolf.watchkitapp data 2>/dev/null || true)

if [ -z "$round_id" ]; then
    round_id=$(python3 -c '
import json, sys
active = [r["id"] for r in json.load(open(sys.argv[1])) if r.get("status") == "active"]
if len(active) != 1:
    sys.exit("expected one active round, found %d; pass the round id" % len(active))
print(active[0])' "$phone_dir/Documents/rounds.json")
fi

xcrun simctl terminate "$phone" golf.spot.SpotGolf 2>/dev/null || true
if [ -n "$watch_dir" ]; then
    xcrun simctl terminate "$watch" golf.spot.SpotGolf.watchkitapp 2>/dev/null || true
fi

reset() {
    local docs=$1 label=$2
    if [ ! -f "$docs/rounds.json" ]; then
        echo "$label: no rounds.json"
        return
    fi
    python3 - "$docs" "$label" "$round_id" <<'EOF'
import json, os, shutil, sys, time
docs, label, wanted = sys.argv[1], sys.argv[2], sys.argv[3]
path = os.path.join(docs, "rounds.json")
rounds = json.load(open(path))
matches = [r for r in rounds if r["id"].lower() == wanted.lower()]
if not matches:
    print(f"{label}: round {wanted} not found")
    sys.exit()
round = matches[0]
shutil.copy(path, path + "." + time.strftime("%Y%m%d-%H%M%S") + ".bak")
before = (len(round["holeTimeline"]), sum(len(h["strokes"]) for h in round["holes"]))
round["holeTimeline"] = round["holeTimeline"][:1]
for hole in round["holes"]:
    hole["strokes"] = []
round["strokesVersion"] = round.get("strokesVersion", 0) + 1
with open(path, "w") as f:
    json.dump(rounds, f, ensure_ascii=False)

# Hidden suggestions: JSONEncoder writes [UUID: [UUID]] as a flat list of key, value, key, value
spath = os.path.join(docs, "suggestions.json")
hidden = 0
if os.path.exists(spath):
    flat = json.load(open(spath))
    kept = []
    for key, value in zip(flat[0::2], flat[1::2]):
        if key.lower() == round["id"].lower():
            hidden = len(value)
        else:
            kept += [key, value]
    with open(spath, "w") as f:
        json.dump(kept, f)
print(f"{label}: round {round['id']}: timeline {before[0]} -> 1 entries, strokes {before[1]} -> 0, hidden suggestions {hidden} -> 0")
EOF
}

reset "$phone_dir/Documents" "Phone"
if [ -n "$watch_dir" ]; then
    reset "$watch_dir/Documents" "Watch"
fi

xcrun simctl launch "$phone" golf.spot.SpotGolf >/dev/null
echo "SpotGolf relaunched on $phone"
