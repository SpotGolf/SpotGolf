#!/usr/bin/env python3
"""Exports one round from the phone and the watch into one folder, for replaying on simulators.

    Scripts/export-round.py --list                          rounds on the phone
    Scripts/export-round.py [--round ID|YYYY-MM-DD|course]  [--phone UDID] [--watch UDID] [--out FOLDER] [--force]

The round defaults to the latest one on the phone. The phone and watch default to the first
physical iPhone and Apple Watch `devicectl` lists. Nothing on the devices is changed.

Every time in the folder is `t`, seconds since the round started (the round's date on the phone).
Sensor clips use the mock sensors' format from SensorSources, with `t` from the clip's start, and
`clips.csv` says when each clip starts. See the README section at the end of this file for the
layout.
"""

import argparse
import csv
import datetime as dt
import gzip
import json
import os
import re
import shutil
import sqlite3
import struct
import subprocess
import sys
import tempfile
import time
import uuid

# The repository: this script's folder is Scripts/ inside it
ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
PHONE_BUNDLE = "golf.spot.SpotGolf"
WATCH_BUNDLE = "golf.spot.SpotGolf.watchkitapp"
STORE = "Library/Application Support/default.store"
CAPTURES = "Documents/putt-captures"
# SwiftData dates are seconds since 2001
APPLE_EPOCH = 978307200.0
EXPORT_VERSION = 1
RECORD_SIZE = 25
ACCEL_SIZE = 20
MOTION_SIZE = 60
SAMPLE_RATE = 48000


def fail(message):
    sys.exit(f"export-round: {message}")


def warn(message):
    print(f"warning: {message}", file=sys.stderr)


# MARK: - devicectl

def devicectl(*args, json_out=True):
    """Runs `xcrun devicectl` and returns its JSON result, or raises with its error text."""
    with tempfile.NamedTemporaryFile(suffix=".json") as out:
        command = ["xcrun", "devicectl", *args]
        if json_out:
            command += ["--json-output", out.name]
        run = subprocess.run(command, capture_output=True, text=True)
        if run.returncode != 0:
            raise RuntimeError((run.stderr or run.stdout).strip().splitlines()[-1:] or ["devicectl failed"])
        if json_out:
            with open(out.name) as f:
                return json.load(f).get("result", {})
        return None


def retried(what, action, tries=6):
    """The link to a device drops when it sleeps, so each call is tried a few times."""
    for attempt in range(1, tries + 1):
        try:
            return action()
        except RuntimeError as error:
            if attempt == tries:
                fail(f"{what} failed after {tries} tries: {error}. Wake the device and keep it near the Mac")
            time.sleep(min(2 * attempt, 10))


def find_devices(phone, watch):
    devices = retried("Listing devices", lambda: devicectl("list", "devices"))["devices"]

    def pick(kind, udid):
        for device in devices:
            hardware = device.get("hardwareProperties", {})
            if udid and udid in (hardware.get("udid"), device.get("identifier")):
                return hardware.get("udid"), device.get("deviceProperties", {}).get("name")
            if not udid and hardware.get("deviceType") == kind and hardware.get("reality") == "physical":
                return hardware.get("udid"), device.get("deviceProperties", {}).get("name")
        fail(f"no {kind} found{' with UDID ' + udid if udid else ''}")

    return pick("iPhone", phone), pick("appleWatch", watch)


def list_files(udid, bundle):
    """Every file in the app's data container: (path, size)."""
    result = retried(f"Listing files on {udid}", lambda: devicectl(
        "device", "info", "files", "--device", udid, "--domain-type", "appDataContainer",
        "--domain-identifier", bundle))
    return [(f["name"], f.get("metadata", {}).get("size", 0)) for f in result.get("files", [])
            if not f.get("resources", {}).get("isDirectory")]


def copy_file(udid, bundle, source, destination, size=None):
    os.makedirs(os.path.dirname(destination), exist_ok=True)

    def copy():
        devicectl("device", "copy", "from", "--device", udid, "--domain-type", "appDataContainer",
                  "--domain-identifier", bundle, "--source", source, "--destination", destination, json_out=False)
        # A store's files grow while the app runs, so only other files are checked
        if size is not None and not source.startswith(STORE) and os.path.getsize(destination) != size:
            raise RuntimeError(f"got {os.path.getsize(destination)} bytes of {size}")

    retried(f"Copying {source}", copy)


def skipped(path):
    """Files that are the system's, not the app's: caches, snapshots, saved window state."""
    return (path.startswith("Library/Caches/") or path.startswith("Library/SplashBoard/")
            or path.startswith("Library/Saved Application State/") or path.endswith(".ktx"))


# MARK: - Stores

def open_store(folder):
    path = os.path.join(folder, STORE)
    if not os.path.exists(path):
        return None
    # A copy in the export's own folder, so opening it never writes into raw/
    work = tempfile.mkdtemp()
    for suffix in ("", "-wal", "-shm"):
        if os.path.exists(path + suffix):
            shutil.copy(path + suffix, os.path.join(work, "default.store" + suffix))
    return sqlite3.connect(os.path.join(work, "default.store"))


def columns(db, table):
    return [row[1] for row in db.execute(f"PRAGMA table_info({table})")]


def column_types(db, table):
    return {row[1]: row[2] for row in db.execute(f"PRAGMA table_info({table})")}


def to_uuid(blob):
    return str(uuid.UUID(bytes=bytes(blob))).upper() if blob is not None and len(blob) == 16 else None


def iso(epoch):
    if epoch is None:
        return None
    return dt.datetime.fromtimestamp(epoch, dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def apple_to_epoch(value):
    return None if value is None else value + APPLE_EPOCH


def decode_row(db, table, row):
    """A SwiftData row as JSON: dates as ISO strings, UUIDs as strings, JSON blobs parsed."""
    types = column_types(db, table)
    out = {}
    for name, value in zip(columns(db, table), row):
        if name.startswith("Z_"):
            continue
        key = name[1].lower() + name[2:].lower() if name.startswith("Z") else name
        kind = types.get(name, "")
        if kind == "TIMESTAMP":
            out[key] = iso(apple_to_epoch(value))
        elif isinstance(value, bytes):
            if len(value) == 16:
                out[key] = to_uuid(value)
            else:
                try:
                    out[key] = json.loads(value)
                except (ValueError, UnicodeDecodeError):
                    out[key] = value.hex()
        else:
            out[key] = value
    return out


def rounds(db):
    found = []
    for rid, date, ended, status, selection in db.execute(
            "SELECT ZID, ZDATE, ZENDEDAT, ZSTATUS, ZCOURSESELECTION FROM ZROUND ORDER BY ZDATE"):
        course = json.loads(selection).get("course", {}).get("name", "?")
        count = db.execute("SELECT count(*) FROM ZSTREAMENTRY WHERE ZROUNDID = ?", (rid,)).fetchone()[0]
        found.append({"id": to_uuid(rid), "blob": rid, "start": apple_to_epoch(date), "end": apple_to_epoch(ended),
                      "status": status, "course": course, "records": count})
    return found


def pick_round(all_rounds, wanted):
    if not all_rounds:
        fail("the phone has no rounds")
    if not wanted:
        return all_rounds[-1]
    lowered = wanted.lower()
    matches = [r for r in all_rounds if r["id"].lower().startswith(lowered)
               or dt.datetime.fromtimestamp(r["start"]).strftime("%Y-%m-%d") == wanted
               or lowered in r["course"].lower()]
    if len(matches) == 1:
        return matches[0]
    if not matches:
        fail(f"no round matches {wanted}; --list shows them")
    print_rounds(matches)
    fail(f"{len(matches)} rounds match {wanted}; pass the round ID")


def print_rounds(all_rounds):
    for r in all_rounds:
        start = dt.datetime.fromtimestamp(r["start"]).strftime("%Y-%m-%d %H:%M")
        length = f"{(r['end'] - r['start']) / 60:.0f} min" if r["end"] else "-"
        print(f"{r['id']}  {start}  {length:>8}  {r['status']:<7} {r['records']:>6} records  {r['course']}")


# MARK: - Stream

def event_names():
    """`StreamEvent.Code` cases by raw value, read from the app's source so the two never drift."""
    path = os.path.join(ROOT, "Shared/Models/StreamEvent.swift")
    try:
        with open(path) as f:
            return {int(value): name for name, value in re.findall(r"case (\w+) = (\d+)", f.read())}
    except OSError:
        return {}


def decode_record(record):
    """One 25-byte `StreamRecord`: (kind, epoch seconds, fields)."""
    kind = record[0]
    if kind == 0:
        ms, lat, lon, alt, acc = struct.unpack_from("<qiiii", record, 1)
        unknown = -2 ** 31
        return "fix", ms / 1000, {"lat": lat / 1e7, "lon": lon / 1e7,
                                  "alt": "" if alt == unknown else alt / 100,
                                  "hacc": "" if acc == unknown else acc / 100}
    ms = struct.unpack_from("<q", record, 1)[0] / 1000
    if kind == 1:
        return "swing", ms, {"peakG": struct.unpack_from("<f", record, 9)[0]}
    if kind in (2, 4):
        score, burst, click, turning = struct.unpack_from("<ffff", record, 9)
        return "contact", ms, {"score": score, "burst": burst, "click": click, "turning": turning,
                               "gated": 1 if kind == 4 else 0}
    if kind == 3:
        code, value = struct.unpack_from("<Hf", record, 9)
        return "event", ms, {"code": code, "value": value}
    return None, ms, {"kind": kind}


# MARK: - Writing

def write_csv(path, header, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)
    return len(rows)


def seconds(value):
    return f"{value:.3f}"


def number(value):
    return value if value == "" else f"{value:.6g}"


def ordered_holes(selection):
    """`CourseSelection.orderedHoles`: each selected nine in order, its holes by number."""
    course = selection.get("course", {})
    holes = []
    for index in selection.get("selectedSubCourseIndices", []):
        nine = course.get("subCourses", [])[index]
        for hole in sorted(nine.get("holes", []), key=lambda h: h.get("number", 0)):
            holes.append((nine.get("name", ""), hole))
    return holes


def read_wav(path):
    """(format, bits, rate, channels, data offset, data bytes) of a PCM or float WAV."""
    with open(path, "rb") as f:
        header = f.read(12)
        if header[:4] != b"RIFF" or header[8:12] != b"WAVE":
            raise ValueError("not a WAV file")
        fmt = None
        while True:
            chunk = f.read(8)
            if len(chunk) < 8:
                raise ValueError("no data chunk")
            name, size = chunk[:4], struct.unpack("<I", chunk[4:])[0]
            if name == b"fmt ":
                body = f.read(size)
                audio_format, channels, rate, _, _, bits = struct.unpack_from("<HHIIHH", body)
                if audio_format == 0xFFFE:
                    audio_format = struct.unpack_from("<H", body, 24)[0]
                fmt = (audio_format, bits, rate, channels)
            elif name == b"data":
                if fmt is None:
                    raise ValueError("data before fmt")
                return (*fmt, f.tell(), size)
            else:
                f.seek(size + (size & 1), 1)


def write_wav(path, audio_format, bits, rate, data):
    channels = 1
    block = channels * bits // 8
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVE")
        f.write(b"fmt " + struct.pack("<IHHIIHH", 16, audio_format, channels, rate, rate * block, block, bits))
        f.write(b"data" + struct.pack("<I", len(data)))
        f.write(data)


def clip_audio(segment, clip, lead):
    """The segment's audio laid out on the clip's clock from `audio-buffers.csv`: each buffer at its
    capture time less `lead`, so a mic gap is silence in the right place. Returns seconds of audio."""
    source = os.path.join(segment, "audio.wav")
    buffers = os.path.join(segment, "audio-buffers.csv")
    if not (os.path.exists(source) and os.path.exists(buffers)):
        return 0
    audio_format, bits, rate, channels, offset, size = read_wav(source)
    if channels != 1:
        warn(f"{source} has {channels} channels; copied as it is")
        shutil.copy(source, os.path.join(clip, "audio.wav"))
        return 0
    frame = bits // 8
    with open(source, "rb") as f:
        f.seek(offset)
        samples = f.read(size)
    out = bytearray()
    with open(buffers) as f:
        for row in csv.DictReader(f):
            t, frames, first = float(row["t"]), int(row["frames"]), int(row["firstFrame"])
            chunk = samples[first * frame:(first + frames) * frame]
            at = round((t - lead) * rate)
            if at < 0:
                chunk = chunk[-at * frame:]
                at = 0
            end = at * frame + len(chunk)
            if len(out) < end:
                out.extend(bytes(end - len(out)))
            out[at * frame:end] = chunk
    write_wav(os.path.join(clip, "audio.wav"), audio_format, bits, rate, bytes(out))
    return len(out) / frame / rate


def binary_to_csv(source, destination, size, header, fmt, lead):
    """`accel.bin` or `motion.bin` records as the mock sensors' CSV. Returns the reading count."""
    if not os.path.exists(source):
        return 0
    count = 0
    with open(source, "rb") as f, open(destination, "w") as out:
        out.write(",".join(header) + "\n")
        while True:
            record = f.read(size)
            if len(record) < size:
                break
            values = struct.unpack(fmt, record)
            out.write(f"{values[0] - lead:.6f}," + ",".join(f"{v:.7g}" for v in values[1:]) + "\n")
            count += 1
    return count


def first_time(segment):
    """The earliest reading in the segment, in seconds from its start: the minimum over the
    accelerometer, device motion and the first audio buffer."""
    times = []
    for name, size in (("accel.bin", ACCEL_SIZE), ("motion.bin", MOTION_SIZE)):
        path = os.path.join(segment, name)
        if os.path.exists(path):
            with open(path, "rb") as f:
                while record := f.read(size * 4096):
                    times.extend(struct.unpack_from("<d", record, i)[0] for i in range(0, len(record) - size + 1, size))
    buffers = os.path.join(segment, "audio-buffers.csv")
    if os.path.exists(buffers):
        with open(buffers) as f:
            times.extend(float(row["t"]) for row in csv.DictReader(f))
    return min(times, default=0.0)


def shift_csv(source, rows, offset, extra):
    """Rows of a segment CSV with its `t` moved onto the round's clock and `extra` put first."""
    if not os.path.exists(source):
        return None
    with open(source) as f:
        reader = csv.reader(f)
        header = next(reader, None)
        if not header:
            return None
        for row in reader:
            if not row:
                continue
            try:
                row[0] = seconds(float(row[0]) + offset)
            except ValueError:
                pass
            rows.append([row[0], *extra, *row[1:]])
    return header


# MARK: - Export

def export(args):
    (phone, phone_name), (watch, watch_name) = find_devices(args.phone, args.watch)
    print(f"Phone: {phone_name} ({phone})\nWatch: {watch_name} ({watch})")
    work = tempfile.mkdtemp(prefix="export-round-")
    raw_phone, raw_watch = os.path.join(work, "phone"), os.path.join(work, "watch")

    print("Listing files")
    phone_files = list_files(phone, PHONE_BUNDLE)
    watch_files = list_files(watch, WATCH_BUNDLE)
    phone_sizes = dict(phone_files)

    print("Copying the phone's store")
    for suffix in ("", "-wal", "-shm"):
        if STORE + suffix in phone_sizes:
            copy_file(phone, PHONE_BUNDLE, STORE + suffix, os.path.join(raw_phone, STORE + suffix))
    db = open_store(raw_phone)
    if db is None:
        fail("the phone has no store")
    all_rounds = rounds(db)
    if args.list:
        print_rounds(all_rounds)
        return
    chosen = pick_round(all_rounds, args.round)
    rid, start = chosen["id"], chosen["start"]
    print(f"Round {rid}: {chosen['course']}, {dt.datetime.fromtimestamp(start):%Y-%m-%d %H:%M}")

    slug = re.sub(r"[^a-z0-9]+", "-", chosen["course"].lower()).strip("-")
    out = args.out or os.path.join(ROOT, "Data/Simulations", f"{slug}-{dt.datetime.fromtimestamp(start):%Y-%m-%d}")
    if os.path.exists(out):
        if not args.force:
            fail(f"{out} exists; pass --force to replace it")
        shutil.rmtree(out)

    # Every other file on both devices, except Putt Lab captures of other rounds
    copied = {STORE, STORE + "-wal", STORE + "-shm"}
    for path, size in phone_files:
        if path not in copied and not skipped(path):
            copy_file(phone, PHONE_BUNDLE, path, os.path.join(raw_phone, path), size)
    print("Copying the watch's files")
    capture_metas = [path for path, _ in watch_files if path.startswith(CAPTURES + "/") and path.endswith("/meta.json")]
    round_captures = set()
    for path in capture_metas:
        local = os.path.join(raw_watch, path)
        copy_file(watch, WATCH_BUNDLE, path, local)
        with open(local) as f:
            if json.load(f).get("roundID", "").upper() == rid:
                round_captures.add(path.split("/")[2])
    for path, size in watch_files:
        if skipped(path) or path in capture_metas and path.split("/")[2] in round_captures:
            continue
        if path.startswith(CAPTURES + "/") and path.split("/")[2] not in round_captures:
            continue
        print(f"  {path} ({size / 1e6:.1f} MB)" if size > 1e6 else f"  {path}")
        copy_file(watch, WATCH_BUNDLE, path, os.path.join(raw_watch, path), size)
    # Metas of other rounds' captures were only needed to find this round's
    for path in capture_metas:
        if path.split("/")[2] not in round_captures:
            os.remove(os.path.join(raw_watch, path))
            shutil.rmtree(os.path.join(raw_watch, CAPTURES, path.split("/")[2]), ignore_errors=True)

    os.makedirs(out)
    shutil.move(work, os.path.join(out, "raw"))
    raw_phone, raw_watch = os.path.join(out, "raw/phone"), os.path.join(out, "raw/watch")
    build(out, raw_phone, raw_watch, rid, {"phone": {"udid": phone, "name": phone_name},
                                           "watch": {"udid": watch, "name": watch_name}})


def build(out, raw_phone, raw_watch, rid, devices):
    """Writes the folder from the files in raw/."""
    db = open_store(raw_phone)
    watch_db = open_store(raw_watch)
    rid_blob = uuid.UUID(rid).bytes
    row = db.execute("SELECT * FROM ZROUND WHERE ZID = ?", (rid_blob,)).fetchone()
    if row is None:
        fail(f"the phone has no round {rid}")
    round_row = decode_row(db, "ZROUND", row)
    start = apple_to_epoch(db.execute("SELECT ZDATE FROM ZROUND WHERE ZID = ?", (rid_blob,)).fetchone()[0])
    end = apple_to_epoch(db.execute("SELECT ZENDEDAT FROM ZROUND WHERE ZID = ?", (rid_blob,)).fetchone()[0])
    watch_round = None
    if watch_db:
        found = watch_db.execute("SELECT * FROM ZROUND WHERE ZID = ?", (rid_blob,)).fetchone()
        watch_round = decode_row(watch_db, "ZROUND", found) if found else None

    def t(epoch):
        return seconds(epoch - start)

    selection = round_row.get("courseselection", {})
    holes = ordered_holes(selection)
    timeline = os.path.join(out, "timeline")
    counts = {}

    # The stream: the phone's, with records only the watch still has added
    stream = dict(db.execute("SELECT ZINDEX, ZRECORD FROM ZSTREAMENTRY WHERE ZROUNDID = ?", (rid_blob,)).fetchall())
    if watch_db:
        for index, record in watch_db.execute("SELECT ZINDEX, ZRECORD FROM ZSTREAMENTRY WHERE ZROUNDID = ?",
                                              (rid_blob,)):
            if index not in stream:
                stream[index] = record
            elif stream[index] != record:
                warn(f"stream record {index} differs between the phone and the watch; kept the phone's")
    missing = [i for i in range(max(stream, default=-1) + 1) if i not in stream]
    if missing:
        warn(f"{len(missing)} stream records are on neither device, first at index {missing[0]}")
    names = event_names()
    fixes, swings, contacts, events = [], [], [], []
    with open(os.path.join(out, "stream.bin"), "wb") as raw:
        for index in sorted(stream):
            record = bytes(stream[index])
            raw.write(record)
            kind, epoch, f = decode_record(record)
            when = [t(epoch), index, iso(epoch)]
            if kind == "fix":
                fixes.append([*when, f"{f['lat']:.7f}", f"{f['lon']:.7f}", number(f["alt"]), number(f["hacc"])])
            elif kind == "swing":
                swings.append([*when, f"{f['peakG']:.3f}"])
            elif kind == "contact":
                contacts.append([*when, *(f"{f[k]:.5g}" for k in ("score", "burst", "click", "turning")), f["gated"]])
            elif kind == "event":
                events.append([*when, f["code"], names.get(f["code"], ""), f"{f['value']:.6g}"])
            else:
                warn(f"stream record {index} has unknown kind {f['kind']}")
    when = ["t", "index", "time"]
    counts["fixes"] = write_csv(os.path.join(timeline, "fixes.csv"), [*when, "lat", "lon", "alt", "hacc"], fixes)
    counts["swings"] = write_csv(os.path.join(timeline, "swings.csv"), [*when, "peakG"], swings)
    counts["contacts"] = write_csv(os.path.join(timeline, "contacts.csv"),
                                   [*when, "score", "burst", "click", "turning", "gated"], contacts)
    counts["events"] = write_csv(os.path.join(timeline, "events.csv"), [*when, "code", "name", "value"], events)
    counts["streamRecords"] = len(stream)

    # Log lines of the round from both stores, and lines with no round written while it ran
    logs = {}
    window_end = (end or start) + 300
    for store, source in ((db, "phone store"), (watch_db, "watch store")):
        if store is None:
            continue
        for device, seq, stamp, level, category, message, owner in store.execute(
                "SELECT ZDEVICE, ZSEQ, ZTIMESTAMP, ZLEVEL, ZCATEGORY, ZMESSAGE, ZROUNDID FROM ZLOGENTRY"):
            epoch = apple_to_epoch(stamp)
            ours = owner == rid_blob
            if not ours and not (owner is None and start - 300 <= epoch <= window_end):
                continue
            logs.setdefault((device, seq, stamp, message),
                            [t(epoch), iso(epoch), device, seq, level, category, message, "round" if ours else "none",
                             source])
    log_rows = sorted(logs.values(), key=lambda r: (float(r[0]), r[2], r[3]))
    counts["logLines"] = write_csv(os.path.join(timeline, "log.csv"),
                                   ["t", "time", "device", "seq", "level", "category", "message", "roundID", "from"],
                                   log_rows)

    # Strokes, hole starts and pins
    stroke_rows = []
    for index, hole in enumerate(round_row.get("holes", [])):
        nine, info = holes[index] if index < len(holes) else ("", {})
        for number_, stroke in enumerate(hole.get("strokes", []), 1):
            hit = apple_to_epoch(stroke.get("hitAt"))
            origin = stroke.get("origin", {})
            origin_text = next(iter(origin), "") if isinstance(origin, dict) else str(origin)
            suggestion = origin.get("suggestion", {}).get("id", "") if isinstance(origin, dict) else ""
            stroke_rows.append([t(hit) if hit else "", index, info.get("number", ""), nine, number_,
                                stroke.get("latitude"), stroke.get("longitude"), stroke.get("clubID", ""),
                                stroke.get("quality", ""), stroke.get("penaltyStrokes", 0), origin_text, suggestion,
                                stroke.get("id", "")])
    counts["strokes"] = write_csv(os.path.join(timeline, "strokes.csv"),
                                  ["t", "holeIndex", "hole", "nine", "stroke", "lat", "lon", "club", "quality",
                                   "penalties", "origin", "suggestionID", "id"], stroke_rows)
    hole_rows = []
    for index, info in enumerate(holes):
        starts = round_row.get("holestarts") or []
        pins = round_row.get("pins") or []
        hole_start = apple_to_epoch(starts[index]) if index < len(starts) and starts[index] is not None else None
        pin = pins[index] if index < len(pins) and pins[index] else {}
        set_at = apple_to_epoch(pin.get("setAt")) if pin.get("setAt") is not None else None
        hole_rows.append([t(hole_start) if hole_start else "", index, info[1].get("number", ""), info[0],
                          info[1].get("par", ""), pin.get("latitude", ""), pin.get("longitude", ""),
                          pin.get("source", ""), t(set_at) if set_at else ""])
    write_csv(os.path.join(timeline, "holes.csv"),
              ["t", "holeIndex", "hole", "nine", "par", "pinLat", "pinLon", "pinSource", "pinSetT"], hole_rows)

    # Putt Lab: each green's segment as a mock sensor clip, and its CSVs on the round's clock
    greens = []
    clip_rows = []
    merged = {name: [] for name in ("contacts", "candidates", "events", "locations", "marks")}
    headers = {}
    captures_root = os.path.join(raw_watch, CAPTURES)
    segments = []
    if os.path.isdir(captures_root):
        for capture in sorted(os.listdir(captures_root)):
            for name in sorted(os.listdir(os.path.join(captures_root, capture))):
                folder = os.path.join(captures_root, capture, name)
                if os.path.exists(os.path.join(folder, "meta.json")):
                    segments.append((capture, name, folder))
    for capture, name, folder in segments:
        with open(os.path.join(folder, "meta.json")) as f:
            meta = json.load(f)
        seg_start = dt.datetime.fromisoformat(meta["startDate"].replace("Z", "+00:00")).timestamp()
        # The first batch holds readings from just before the segment started, so the clip starts
        # at its earliest reading: every t in it is then 0 or more, and nothing is dropped
        lead = min(0.0, first_time(folder))
        offset = seg_start - start + lead
        clip_name = f"{name}.clip"
        clip = os.path.join(out, "clips", clip_name)
        os.makedirs(clip)
        print(f"  {clip_name}")
        accel = binary_to_csv(os.path.join(folder, "accel.bin"), os.path.join(clip, "accelerometer.csv"),
                              ACCEL_SIZE, ["t", "x", "y", "z"], "<dfff", lead)
        motion = binary_to_csv(os.path.join(folder, "motion.bin"), os.path.join(clip, "motion.csv"), MOTION_SIZE,
                               ["t", "rx", "ry", "rz", "ux", "uy", "uz", "gx", "gy", "gz", "qx", "qy", "qz", "qw"],
                               "<d13f", lead)
        audio = clip_audio(folder, clip, lead)
        duration = meta.get("duration") or 0
        clip_rows.append([seconds(offset), seconds(duration), f"clips/{clip_name}", meta.get("hole", ""),
                          meta.get("segment", ""), accel, motion, f"{audio:.3f}"])
        extra = [meta.get("segment", ""), meta.get("hole", "")]
        for kind in merged:
            source = os.path.join(folder, f"{kind}.csv")
            # Locations are on the segment's date clock and the rest on its uptime clock; both start at the segment's start
            header = shift_csv(source, merged[kind], offset - lead, extra)
            if header:
                headers[kind] = header
        greens.append({"t": round(offset, 3), "clip": f"clips/{clip_name}", "capture": capture, "meta": meta})
    if segments:
        write_csv(os.path.join(out, "clips.csv"),
                  ["t", "duration", "clip", "hole", "segment", "accelerometerReadings", "motionReadings",
                   "audioSeconds"], clip_rows)
        for kind, rows in merged.items():
            if kind in headers:
                rows.sort(key=lambda r: float(r[0]) if r[0] else 0)
                write_csv(os.path.join(timeline, f"green-{kind}.csv"),
                          [headers[kind][0], "segment", "hole", *headers[kind][1:]], rows)
    else:
        warn("the watch has no Putt Lab capture for this round, so there are no sensor clips")
    counts["clips"] = len(segments)

    # The rest of the round: course, bag, settings
    with open(os.path.join(out, "course.json"), "w") as f:
        json.dump(selection, f, indent=2)
    bag = {club: distance for club, distance in db.execute("SELECT ZCLUBID, ZDISTANCE FROM ZCARRIEDCLUB")}

    def prefs(folder, bundle):
        import plistlib
        path = os.path.join(folder, f"Library/Preferences/{bundle}.plist")
        if not os.path.exists(path):
            return None
        with open(path, "rb") as f:
            return json.loads(json.dumps(plistlib.load(f), default=str))

    summary = {
        "exportVersion": EXPORT_VERSION,
        "exportedAt": iso(time.time()),
        "roundID": rid,
        "course": selection.get("course", {}).get("name"),
        "tee": selection.get("teeName"),
        "start": iso(start),
        "startEpoch": start,
        "end": iso(end),
        "duration": round(end - start, 3) if end else None,
        "clock": "Every t is seconds since start. Stream, clip and watch log times are the watch's clock; "
                 "the start, strokes, pins and phone log times are the phone's",
        "devices": devices,
        "counts": counts,
        "greens": greens,
        "bag": bag,
        "settings": {"phone": prefs(raw_phone, PHONE_BUNDLE), "watch": prefs(raw_watch, WATCH_BUNDLE)},
        "round": round_row,
        "watchRound": watch_round,
    }
    del summary["round"]["courseselection"]
    with open(os.path.join(out, "round.json"), "w") as f:
        json.dump(summary, f, indent=2)
    print(f"\nWrote {out}")
    for key, value in counts.items():
        print(f"  {key}: {value}")


def path_arg(value):
    """A path argument as an absolute path: ~ expanded, relative to the current directory."""
    return os.path.abspath(os.path.expanduser(value))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--list", action="store_true", help="list the phone's rounds")
    parser.add_argument("--round", help="round ID (or its start), date YYYY-MM-DD, or part of the course name")
    parser.add_argument("--phone", help="phone UDID")
    parser.add_argument("--watch", help="watch UDID")
    parser.add_argument("--out", type=path_arg, help="folder to write; Data/Simulations/<course>-<date> by default")
    parser.add_argument("--force", action="store_true", help="replace the folder if it exists")
    parser.add_argument("--rebuild", metavar="FOLDER", type=path_arg, help="write the folder again from its raw/ files, no devices")
    parser.add_argument("--round-id", help="with --rebuild: the round, when raw/ holds more than one")
    args = parser.parse_args()
    if args.rebuild:
        folder = args.rebuild
        summary = os.path.join(folder, "round.json")
        rid = args.round_id
        devices = {}
        if os.path.exists(summary):
            with open(summary) as f:
                old = json.load(f)
            rid, devices = rid or old["roundID"], old.get("devices", {})
        if not rid:
            fail("pass --round-id")
        for name in os.listdir(folder):
            if name != "raw":
                path = os.path.join(folder, name)
                shutil.rmtree(path) if os.path.isdir(path) else os.remove(path)
        build(folder, os.path.join(folder, "raw/phone"), os.path.join(folder, "raw/watch"), rid.upper(), devices)
        return
    export(args)


if __name__ == "__main__":
    main()

# README
#
# Data/Simulations/<course>-<date>/
#   round.json          The round: ID, course, tee, start, end, counts, settings on both devices, club
#                       distances, each green's clip with its Putt Lab meta, and every stored round field
#                       from the phone (round) and the watch (watchRound)
#   course.json         The round's CourseSelection, with the whole course
#   stream.bin          The watch's stream as the phone stores it: 25-byte StreamRecords in index order
#   clips.csv           t,duration,clip,...: when each green's sensor clip starts
#   clips/NNN-holeH.clip/
#                       A Putt Lab segment in the mock sensors' format: accelerometer.csv (800 Hz),
#                       motion.csv (200 Hz), audio.wav (48 kHz mono, mic gaps as silence)
#   timeline/           Everything else on the round's clock, `t` first
#     fixes.csv         GPS fixes (1 Hz) from the stream: what a replay sends to both simulators
#     swings.csv        Swings the watch detected
#     contacts.csv      Contacts the watch heard and felt; gated = 1 when the stroke gate passed it
#     events.csv        Workout and sensor events, with the StreamEvent.Code name
#     strokes.csv       The strokes the player kept
#     holes.csv         Each hole's start, par and pin
#     log.csv           Log lines from both devices
#     green-*.csv       The Putt Lab segments' contacts, candidates, events, GPS fixes and marks
#   raw/phone, raw/watch
#                       Every file copied from the apps' containers, untouched (stores, settings, course
#                       cache, this round's Putt Lab capture)
