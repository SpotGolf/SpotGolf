#!/usr/bin/env python3
"""Replays a round folder from export-round.py on a phone and watch simulator pair.

    Scripts/replay-round.py <round folder> [--phone SIMULATOR] [--watch SIMULATOR] [--from MIN] [--to MIN]
    Scripts/replay-round.py <round folder> --holes          when each hole and green starts

1. Sets the round's settings (stationary threshold, green zone, Developer Mode) on the
   phone simulator and relaunches the phone app.
2. Puts both simulators at the round's first GPS fix and asks to continue. Start the round by
   hand on the phone, on the round's course and tee, then answer y (n exits). A round already
   running is used as it is.
3. From the round's start, plays in real time:
   - every GPS fix to both simulators
   - each green's Developer Mode clip to the watch's mock sensors
   - each swing the watch detected away from the greens, as a short accelerometer clip that peaks
     at the swing's force at the swing's time
4. Stops at the end of the round, at --to, when the phone's round ends, or on Ctrl-C.

Every time lines up with the round's start on the phone simulator. With --from, the replay starts
that far into the round, and the round's start counts as that point.

The simulators default to the click-testing pair, SpotGolf Phone and SpotGolf Watch. Both must be
booted with the apps installed. The apps are not changed.
"""

import argparse
import csv
import json
import math
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time

PHONE_BUNDLE = "golf.spot.SpotGolf"
WATCH_BUNDLE = "golf.spot.SpotGolf.watchkitapp"
APPLE_EPOCH = 978307200.0
# Clips go into the watch's inbox this long before they start, with their start time in clip.json
CLIP_LEAD = 20.0
# A swing clip: 800 Hz readings at rest, with the swing's peak SWING_AT seconds in
ACCEL_RATE = 800
SWING_CLIP = 0.25
SWING_AT = 0.1
SETTINGS = {"stationaryThreshold": "-float", "greenZone": "-float", "developerMode": "-bool"}


def fail(message):
    sys.exit(f"replay-round: {message}")


def simctl(*args, check=True):
    run = subprocess.run(["xcrun", "simctl", *args], capture_output=True, text=True)
    if check and run.returncode != 0:
        fail(f"simctl {' '.join(args)}: {(run.stderr or run.stdout).strip()}")
    return run.stdout.strip()


def booted_udid(name):
    devices = json.loads(simctl("list", "devices", "--json"))["devices"]
    for runtime in devices.values():
        for device in runtime:
            if name in (device["name"], device["udid"]):
                if device["state"] != "Booted":
                    fail(f"{device['name']} is not booted")
                return device["udid"]
    fail(f"no simulator named {name}")


def container(udid, bundle):
    path = simctl("get_app_container", udid, bundle, "data", check=False)
    if not path:
        fail(f"{bundle} is not installed on {udid}")
    return path


def read_csv(path):
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return list(csv.DictReader(f))


# MARK: - The phone's round

def phone_round(store):
    """(start epoch, status) of the phone simulator's newest round, or None."""
    if not os.path.exists(store):
        return None
    try:
        db = sqlite3.connect(f"file:{store}?mode=ro", uri=True, timeout=1)
        row = db.execute("SELECT ZDATE, ZSTATUS FROM ZROUND ORDER BY ZDATE DESC LIMIT 1").fetchone()
        db.close()
    except sqlite3.Error:
        return None
    return (row[0] + APPLE_EPOCH, row[1]) if row else None


def wait_for_round(store, started_after):
    """The start of the round running on the phone: one already running, or the next one started."""
    current = phone_round(store)
    if current and current[1] in ("starting", "active"):
        print(f"Using the round already running on the phone, started {time.ctime(current[0])}")
        return current[0]
    print("Waiting for a round to start on the phone simulator")
    while True:
        current = phone_round(store)
        if current and current[1] in ("starting", "active") and current[0] >= started_after - 60:
            print(f"Round started {time.ctime(current[0])}")
            return current[0]
        time.sleep(0.5)


# MARK: - Sending

class Location:
    """Sets both simulators' location, without waiting for one call before the next."""

    def __init__(self, udids):
        self.udids = udids
        self.running = []

    def set(self, lat, lon):
        self.running = [p for p in self.running if p.poll() is None]
        # A fix still being set when the next is due is dropped rather than queued
        if self.running:
            return
        for udid in self.udids:
            self.running.append(subprocess.Popen(["xcrun", "simctl", "location", udid, "set", f"{lat},{lon}"],
                                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))

    def wait(self):
        for process in self.running:
            process.wait()


def send_clip(inbox, name, start_at, source=None, accelerometer=None):
    """Puts a clip in the watch's inbox to start at `start_at`, copied to a hidden name first and then
    renamed, so the mock never reads a half-written clip."""
    # The inbox can go away when the watch app is installed or first launched, so it is made each time
    os.makedirs(inbox, exist_ok=True)
    hidden = os.path.join(inbox, f".{name}")
    shutil.rmtree(hidden, ignore_errors=True)
    if source:
        shutil.copytree(source, hidden)
    else:
        os.makedirs(hidden)
        with open(os.path.join(hidden, "accelerometer.csv"), "w") as f:
            f.write("t,x,y,z\n")
            f.writelines(f"{t:.6f},{x:.6g},{y:.6g},{z:.6g}\n" for t, x, y, z in accelerometer)
    with open(os.path.join(hidden, "clip.json"), "w") as f:
        json.dump({"startAt": start_at}, f)
    final = os.path.join(inbox, name)
    shutil.rmtree(final, ignore_errors=True)
    os.rename(hidden, final)


def swing_readings(peak):
    """A wrist at rest (1 g straight down) with one reading of `peak` g: the swing finder starts a
    swing at the first reading of 3 g or more and takes the highest within 3 s as its force, so
    this gives a swing at the clip's SWING_AT with exactly that force."""
    readings = []
    spike = round(SWING_AT * ACCEL_RATE)
    for i in range(round(SWING_CLIP * ACCEL_RATE)):
        g = peak if i == spike else 1.0
        readings.append((i / ACCEL_RATE, 0.0, 0.0, -g))
    return readings


# MARK: - Replay

def schedule(folder, start_t, end_t):
    """Everything to send, as (t, kind, data), in time order."""
    events = []
    clips = read_csv(os.path.join(folder, "clips.csv"))
    windows = []
    for clip in clips:
        t, duration = float(clip["t"]), float(clip["duration"])
        windows.append((t, t + duration + 3))
        if t + duration >= start_t and t <= end_t:
            events.append((t, "clip", clip))
    for swing in read_csv(os.path.join(folder, "timeline/swings.csv")):
        t = float(swing["t"])
        # Swings on a green are in that green's clip already
        if start_t <= t <= end_t and not any(a <= t <= b for a, b in windows):
            events.append((t, "swing", swing))
    for fix in read_csv(os.path.join(folder, "timeline/fixes.csv")):
        t = float(fix["t"])
        if start_t <= t <= end_t:
            events.append((t, "fix", fix))
    for hole in read_csv(os.path.join(folder, "timeline/holes.csv")):
        if hole["t"] and start_t <= float(hole["t"]) <= end_t:
            events.append((float(hole["t"]), "hole", hole))
    order = {"hole": 0, "fix": 1, "clip": 2, "swing": 3}
    events.sort(key=lambda e: (e[0], order[e[1]]))
    return events


def print_holes(folder):
    for hole in read_csv(os.path.join(folder, "timeline/holes.csv")):
        start = f"{float(hole['t']) / 60:6.1f} min" if hole["t"] else "     -    "
        print(f"Hole {hole['hole']:>2}  {start}  par {hole['par']}")
    for clip in read_csv(os.path.join(folder, "clips.csv")):
        print(f"Green clip {clip['clip']}  {float(clip['t']) / 60:6.1f} min  {float(clip['duration']):.0f} s")


def apply_settings(phone, settings):
    if not settings:
        return
    for key, flag in SETTINGS.items():
        if key in settings:
            value = settings[key]
            if flag == "-bool":
                value = "true" if value else "false"
            simctl("spawn", phone, "defaults", "write", PHONE_BUNDLE, key, flag, str(value))
    print("Settings: " + ", ".join(f"{k} {settings[k]}" for k in SETTINGS if k in settings))
    simctl("terminate", phone, PHONE_BUNDLE, check=False)
    simctl("launch", phone, PHONE_BUNDLE)


def launch(udid, bundle):
    """Launches the app, or leaves it running. A watch that just booted refuses for a few seconds."""
    for _ in range(10):
        if subprocess.run(["xcrun", "simctl", "launch", udid, bundle], capture_output=True).returncode == 0:
            return
        time.sleep(2)
    fail(f"could not launch {bundle} on {udid}")


def confirm(question):
    """True when the user answers y, False when n. Asks again on anything else."""
    while True:
        try:
            answer = input(f"{question} (y/n)? ").strip().lower()
        except EOFError:
            return False
        if answer in ("y", "n"):
            return answer == "y"


def path_arg(value):
    """A path argument as an absolute path: ~ expanded, relative to the current directory."""
    return os.path.abspath(os.path.expanduser(value))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("folder", type=path_arg, help="a round folder from export-round.py")
    parser.add_argument("--phone", default="SpotGolf Phone", help="phone simulator name or UDID")
    parser.add_argument("--watch", default="SpotGolf Watch", help="watch simulator name or UDID")
    parser.add_argument("--from", dest="start", type=float, default=0, help="minutes into the round to start")
    parser.add_argument("--to", dest="end", type=float, help="minutes into the round to stop")
    parser.add_argument("--holes", action="store_true", help="print when each hole and green starts")
    parser.add_argument("--keep-settings", action="store_true", help="leave the phone's settings as they are")
    args = parser.parse_args()

    folder = args.folder
    with open(os.path.join(folder, "round.json")) as f:
        summary = json.load(f)
    if args.holes:
        print_holes(folder)
        return
    start_t = args.start * 60
    end_t = args.end * 60 if args.end is not None else (summary.get("duration") or math.inf)
    events = schedule(folder, start_t, end_t)
    fixes = [e for e in events if e[1] == "fix"]
    if not fixes:
        fail("no GPS fixes in that part of the round")

    phone, watch = booted_udid(args.phone), booted_udid(args.watch)
    phone_store = os.path.join(container(phone, PHONE_BUNDLE), "Library/Application Support/default.store")
    inbox = os.path.join(container(watch, WATCH_BUNDLE), "Library/SensorMock/Inbox")
    print(f"{summary['course']}, {summary.get('tee')} tee: {len(fixes)} fixes, "
          f"{sum(e[1] == 'swing' for e in events)} swings, {sum(e[1] == 'clip' for e in events)} green clips")

    if not args.keep_settings:
        apply_settings(phone, (summary.get("settings") or {}).get("phone"))
    launch(watch, WATCH_BUNDLE)
    launch(phone, PHONE_BUNDLE)
    location = Location([phone, watch])
    first = fixes[0][2]
    location.set(first["lat"], first["lon"])
    location.wait()
    print(f"Both simulators at the first fix, {first['lat']}, {first['lon']}. "
          f"Start a round on {summary['course']}, {summary.get('tee')} tee")
    asked_at = time.time()
    if not confirm("Round started on the phone simulator? Continue the replay"):
        return
    round_start = wait_for_round(phone_store, asked_at)

    def wall(t):
        return round_start + t - start_t

    # Clips are sent CLIP_LEAD early; everything else when it is due
    sends = []
    for t, kind, data in events:
        due = t - CLIP_LEAD if kind in ("clip", "swing") else t
        sends.append((max(due, start_t), t, kind, data))
    sends.sort(key=lambda s: s[0])
    swings = 0
    last_status_check = 0
    try:
        for due, t, kind, data in sends:
            delay = wall(due) - time.time()
            if delay > 0:
                time.sleep(delay)
            if time.time() - last_status_check > 5:
                last_status_check = time.time()
                current = phone_round(phone_store)
                if current and current[1] == "ended" and abs(current[0] - round_start) < 1:
                    print("The phone's round ended")
                    break
            stamp = f"{t / 60:6.1f} min"
            if kind == "fix":
                if wall(t) >= time.time() - 1:
                    location.set(data["lat"], data["lon"])
            elif kind == "clip":
                name = os.path.basename(data["clip"])
                # A clip that began before --from starts in the past, so the mock plays the rest of it in step
                send_clip(inbox, name, wall(t), source=os.path.join(folder, data["clip"]))
                print(f"{stamp}  green clip {name} queued, {float(data['duration']):.0f} s")
            elif kind == "swing":
                swings += 1
                send_clip(inbox, f"swing-{swings:04d}.clip", wall(t) - SWING_AT,
                          accelerometer=swing_readings(float(data["peakG"])))
                if float(data["peakG"]) >= 10:
                    print(f"{stamp}  swing, {float(data['peakG']):.1f} g")
            elif kind == "hole":
                print(f"{stamp}  hole {data['hole']} starts")
        else:
            print("End of the round's data")
    except KeyboardInterrupt:
        print("\nStopped")
    location.wait()


if __name__ == "__main__":
    main()
