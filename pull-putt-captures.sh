#!/bin/bash
# Pulls the watch's Putt Lab captures to this Mac with devicectl and checks each segment.
#
#   ./pull-putt-captures.sh [--watch <UDID>] [--to <folder>]
#
# Lists Documents/putt-captures in the watch app's container, copies every file that is not
# already here with the same size into <folder>/<captureID>/<segment>/ (default
# Data/putt-captures), then checks each segment's accel.bin and motion.bin sizes and the WAV's
# frame count against meta.json, looks for mic gaps in audio-buffers.csv (version 3 on), and
# prints a summary. devicectl cannot delete, so captures are
# deleted on the watch, on Putt Lab's Captures page, once they are here.
# See plans/2026-10-12-putt-lab-in-rounds.md.
set -euo pipefail

WATCH=""
DEST="$(cd "$(dirname "$0")" && pwd)/Data/putt-captures"
while [ $# -gt 0 ]; do
  case "$1" in
    --watch) WATCH="$2"; shift 2 ;;
    --to) DEST="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

BUNDLE="golf.spot.SpotGolf.watchkitapp"
REMOTE="Documents/putt-captures"

if [ -z "$WATCH" ]; then
  # The first paired physical Apple Watch
  WATCH=$(xcrun devicectl list devices 2>/dev/null \
    | awk '/Apple Watch/ && /physical/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) print $i }' | head -1)
  [ -n "$WATCH" ] || { echo "No paired Apple Watch found; pass --watch <UDID>" >&2; exit 1; }
fi
echo "Watch $WATCH → $DEST"

listing=$(mktemp)
trap 'rm -f "$listing"' EXIT
xcrun devicectl device info files --device "$WATCH" --domain-type appDataContainer \
  --domain-identifier "$BUNDLE" --subdirectory "$REMOTE" --json-output "$listing" >/dev/null 2>&1 \
  || { echo "Could not list $REMOTE on the watch (is it awake and nearby?)" >&2; exit 1; }

# Every file as "path<TAB>size", from the listing's JSON: result.files[], each with a name
# relative to the subdirectory, metadata.size and resources.isDirectory.
files=$(python3 -I - "$listing" <<'EOF'
import json, sys
doc = json.load(open(sys.argv[1]))
if "error" in doc and "result" not in doc:
    desc = doc["error"].get("userInfo", {}).get("NSLocalizedDescription", {}).get("string", "unknown error")
    sys.exit(f"devicectl: {desc}")
for entry in doc.get("result", {}).get("files", []):
    if entry.get("resources", {}).get("isDirectory"):
        continue
    print(f"{entry['name']}\t{entry.get('metadata', {}).get('size', 0)}")
EOF
)

if [ -z "$files" ]; then
  echo "No capture files on the watch."
  exit 0
fi

copied=0
skipped=0
while IFS=$'\t' read -r path size; do
  [ -n "$path" ] || continue
  local_path="$DEST/$path"
  if [ -f "$local_path" ] && [ "$(stat -f %z "$local_path")" = "$size" ]; then
    skipped=$((skipped + 1))
    continue
  fi
  mkdir -p "$(dirname "$local_path")"
  echo "  $path ($size bytes)"
  xcrun devicectl device copy from --device "$WATCH" --domain-type appDataContainer \
    --domain-identifier "$BUNDLE" --source "$REMOTE/$path" --destination "$local_path" >/dev/null
  copied=$((copied + 1))
done <<< "$files"
echo "Copied $copied file(s), $skipped already here."

# Checks and summary
python3 -I - "$DEST" <<'EOF'
import csv, json, os, struct, sys
root = sys.argv[1]
problems = 0

# A mic gap shorter than this is clock jitter between buffers
MIN_GAP = 0.05

def wav_frames(path):
    """Frames in a WAV's data chunk, reading its chunks: AVAudioFile adds JUNK and FLLR chunks, so
    the data chunk does not start at byte 44."""
    with open(path, "rb") as f:
        head = f.read(12)
        if len(head) < 12 or head[:4] != b"RIFF" or head[8:12] != b"WAVE":
            return None
        block = None
        while True:
            chunk = f.read(8)
            if len(chunk) < 8:
                return None
            cid, csize = chunk[:4], struct.unpack("<I", chunk[4:])[0]
            if cid == b"fmt ":
                fmt = f.read(csize)
                block = struct.unpack("<H", fmt[12:14])[0]
                f.seek(csize % 2, 1)
            elif cid == b"data":
                if not block:
                    return None
                # A segment cut short by a kill never had its data size written
                available = os.path.getsize(path) - f.tell()
                return min(csize, available) // block
            else:
                f.seek(csize + csize % 2, 1)

def mic_gaps(path, rate):
    """Gaps between microphone buffers, as (capture time, seconds missing)."""
    gaps = []
    previous_end = None
    with open(path) as f:
        for row in csv.DictReader(f):
            t, frames = float(row["t"]), int(row["frames"])
            if previous_end is not None and t - previous_end > MIN_GAP:
                gaps.append((previous_end, t - previous_end))
            previous_end = t + frames / rate
    return gaps
for capture in sorted(os.listdir(root)):
    cdir = os.path.join(root, capture)
    if not os.path.isdir(cdir):
        continue
    print(f"\nCapture {capture}")
    for segment in sorted(os.listdir(cdir)):
        sdir = os.path.join(cdir, segment)
        meta_path = os.path.join(sdir, "meta.json")
        if not os.path.isdir(sdir) or not os.path.exists(meta_path):
            continue
        meta = json.load(open(meta_path))
        def size(name):
            p = os.path.join(sdir, name)
            return os.path.getsize(p) if os.path.exists(p) else 0
        notes = []
        if meta.get("savesData", True):
            if size("accel.bin") != meta.get("accelCount", 0) * 20:
                notes.append(f"accel.bin is {size('accel.bin')} bytes, expected {meta.get('accelCount', 0) * 20}")
            if size("motion.bin") != meta.get("motionCount", 0) * 60:
                notes.append(f"motion.bin is {size('motion.bin')} bytes, expected {meta.get('motionCount', 0) * 60}")
            wav = os.path.join(sdir, "audio.wav")
            if meta.get("microphone", True) and os.path.exists(wav):
                frames = wav_frames(wav)
                if frames is None or abs(frames - meta.get("audioFrames", 0)) > 4096:
                    notes.append(f"audio.wav has {frames} frames, meta.json says {meta.get('audioFrames', 0)}")
            buffers = os.path.join(sdir, "audio-buffers.csv")
            rate = (meta.get("audio") or {}).get("sampleRate")
            if os.path.exists(buffers) and rate:
                gaps = mic_gaps(buffers, rate)
                if gaps:
                    lost = sum(g for _, g in gaps)
                    first = ", ".join(f"{g:.2f} s at {t:.1f} s" for t, g in gaps[:3])
                    notes.append(f"mic gaps: {len(gaps)}, {lost:.2f} s in all ({first}{', ...' if len(gaps) > 3 else ''})")
        if meta.get("endDate") is None:
            notes.append("not finished")
        marks = len(meta.get("marks", []))
        def rows(name):
            p = os.path.join(sdir, name)
            return max(0, sum(1 for _ in open(p)) - 1) if os.path.exists(p) else 0
        contacts = rows("contacts.csv")
        extras = ""
        if meta.get("version", 1) >= 3:
            extras = (f", {rows('candidates.csv')} candidates, {rows('events.csv')} events, {rows('locations.csv')} fixes"
                      f", {meta.get('wristLocation', '?')} wrist, crown {meta.get('crownOrientation', '?')}")
        battery = ""
        if meta.get("startBattery") is not None and meta.get("endBattery") is not None:
            battery = f", battery {meta['startBattery'] * 100:.0f}% → {meta['endBattery'] * 100:.0f}%"
        hole = meta.get("hole", "?")
        print(f"  {segment}: hole {hole}, {meta.get('duration', 0) or 0:.0f} s, {marks} marks, {contacts} contacts{extras}, "
              f"ended {meta.get('endReason', '?')}{battery}" + (f"  !! {'; '.join(notes)}" if notes else ""))
        problems += len(notes)
print()
print("All segments check out." if problems == 0 else f"{problems} problem(s) found.")
EOF
