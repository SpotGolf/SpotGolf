#!/usr/bin/env python3
"""Pulls the putting sessions players shared from CloudKit to this Mac, and checks each one.

    Scripts/pull-shared-putts.py [--environment development|production] [--to FOLDER] [--keep] [--dry-run]

Talks to the public database of iCloud.golf.spot.SpotGolf with CloudKit Web Services and a
server-to-server key (these keys work only on the public database). The key file's path is in
SPOTGOLF_CK_KEY and its key ID in SPOTGOLF_CK_KEY_ID.

1. Reads every PuttDeletion record and deletes the folders it names on this Mac: one session, or
   every session of the sharer ID. Sessions they name are never downloaded, and their PuttSession
   records still in CloudKit are deleted. The PuttDeletion record is then deleted.
2. Downloads each PuttSession not already here, unpacks its Apple Archive into
   <FOLDER>/<sharerID>/<sessionID>/ (default Data/shared-putts), turns audio.caf back into
   audio.wav (the same samples, so the folder matches a Developer Mode segment that
   analyze-capture.py reads), and checks accel.bin, motion.bin and audio.wav against meta.json.
   A session that fails a check is not kept, and its record stays in CloudKit.
3. Deletes each session's PuttSession record once its folder passes, so CloudKit holds only
   sessions not yet pulled. --keep leaves the records there.
4. Prints a summary of every session on disk.

--dry-run lists what would be deleted and downloaded, and changes nothing here or in CloudKit.
See plans/2026-10-27-putt-data-sharing.md, sections 3 and 4, and the README section at the end
of this file for the layout.
"""

import argparse
import base64
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import wave
from collections import Counter

# The repository: this script's folder is Scripts/ inside it
ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
CONTAINER = "iCloud.golf.spot.SpotGolf"
HOST = "https://api.apple-cloudkit.com"
ACCEL_SIZE = 20
MOTION_SIZE = 60
# CloudKit allows at most 200 records a query and 200 operations a modify
BATCH = 200
# Sharer and session IDs are UUIDs, and become folder names, so nothing else is allowed
ID_PATTERN = re.compile(r"^[A-Za-z0-9-]{1,64}$")


def fail(message):
    sys.exit(f"pull-shared-putts: {message}")


def warn(message):
    print(f"warning: {message}", file=sys.stderr)


# MARK: - CloudKit Web Services

class CloudKit:
    """Signed requests to the public database with a server-to-server key."""

    def __init__(self, environment, key_path, key_id):
        self.subpath = f"/database/1/{CONTAINER}/{environment}/public"
        self.key_path = key_path
        self.key_id = key_id
        self.key = None
        try:
            from cryptography.hazmat.primitives import serialization
            with open(key_path, "rb") as f:
                self.key = serialization.load_pem_private_key(f.read(), password=None)
        except ImportError:
            # Without the cryptography package, openssl signs each request
            pass

    def post(self, path, payload):
        """POSTs JSON to <database>/<path> and returns the JSON answer, or fails with CloudKit's reason."""
        body = json.dumps(payload).encode()
        subpath = f"{self.subpath}/{path}"
        request = urllib.request.Request(HOST + subpath, data=body, method="POST",
                                         headers={"Content-Type": "application/json",
                                                  **sign_headers(self, body, subpath)})
        try:
            with urllib.request.urlopen(request, timeout=60) as answer:
                return json.load(answer)
        except urllib.error.HTTPError as error:
            text = error.read().decode(errors="replace")
            try:
                detail = json.loads(text)
                text = f"{detail.get('serverErrorCode', '')} {detail.get('reason', '')}".strip()
            except ValueError:
                pass
            fail(f"CloudKit {path} answered {error.code}: {text}")
        except urllib.error.URLError as error:
            fail(f"could not reach CloudKit: {error.reason}")

    def query(self, record_type):
        """Every record of the type, following continuationMarker from page to page."""
        records = []
        marker = None
        while True:
            payload = {"query": {"recordType": record_type}, "resultsLimit": BATCH}
            if marker:
                payload["continuationMarker"] = marker
            answer = self.post("records/query", payload)
            for record in answer.get("records", []):
                if "serverErrorCode" in record:
                    warn(f"{record_type} {record.get('recordName')}: {record['serverErrorCode']} {record.get('reason', '')}")
                else:
                    records.append(record)
            marker = answer.get("continuationMarker")
            if not marker:
                return records

    def delete(self, record_names):
        """Deletes the records, whatever their change tags. Returns the names that were deleted."""
        deleted = []
        for start in range(0, len(record_names), BATCH):
            names = record_names[start:start + BATCH]
            answer = self.post("records/modify", {
                "operations": [{"operationType": "forceDelete", "record": {"recordName": n}} for n in names],
                "atomic": False})
            for record in answer.get("records", []):
                if "serverErrorCode" in record:
                    warn(f"could not delete {record.get('recordName')}: {record['serverErrorCode']} {record.get('reason', '')}")
                else:
                    deleted.append(record.get("recordName"))
        return deleted


def sign(key_path, key, message):
    """The ECDSA SHA-256 signature of the message, DER encoded, as CloudKit wants it."""
    if key is not None:
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.asymmetric import ec
        return key.sign(message, ec.ECDSA(hashes.SHA256()))
    run = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path], input=message, capture_output=True)
    if run.returncode != 0:
        fail(f"openssl could not sign with {key_path}: {run.stderr.decode(errors='replace').strip()}")
    return run.stdout


def sign_headers(cloudkit, body, subpath):
    """The three headers of a server-to-server request. The signed message is
    `<date>:<base64 SHA-256 of the body>:<subpath>`; the date is UTC with no fractional seconds."""
    date = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    body_hash = base64.b64encode(hashlib.sha256(body).digest()).decode()
    signature = sign(cloudkit.key_path, cloudkit.key, f"{date}:{body_hash}:{subpath}".encode())
    return {"X-Apple-CloudKit-Request-KeyID": cloudkit.key_id,
            "X-Apple-CloudKit-Request-ISO8601Date": date,
            "X-Apple-CloudKit-Request-SignatureV1": base64.b64encode(signature).decode()}


def field(record, name):
    """A field's value, or None when the record does not have it."""
    return (record.get("fields", {}).get(name) or {}).get("value")


def download(asset, destination):
    """Downloads an Asset field's file. Its downloadURL holds `${f}` where a file name goes."""
    url = asset.get("downloadURL")
    if not url:
        raise RuntimeError("the record's archive has no download URL")
    url = url.replace("${f}", urllib.parse.quote("archive.aar"))
    with urllib.request.urlopen(url, timeout=120) as answer, open(destination, "wb") as out:
        shutil.copyfileobj(answer, out, 1 << 20)
    size = asset.get("size")
    if size is not None and os.path.getsize(destination) != size:
        raise RuntimeError(f"got {os.path.getsize(destination)} bytes of {size}")


# MARK: - Unpacking and checks

def wav_frames(path):
    with wave.open(path, "rb") as w:
        return w.getnframes()


def check(folder):
    """Problems with an unpacked session, as the removed pull-putt-captures.sh found them."""
    with open(os.path.join(folder, "meta.json")) as f:
        meta = json.load(f)

    def size(name):
        path = os.path.join(folder, name)
        return os.path.getsize(path) if os.path.exists(path) else 0

    problems = []
    accel, motion = meta.get("accelCount", 0) * ACCEL_SIZE, meta.get("motionCount", 0) * MOTION_SIZE
    if size("accel.bin") != accel:
        problems.append(f"accel.bin is {size('accel.bin')} bytes, expected {accel}")
    if size("motion.bin") != motion:
        problems.append(f"motion.bin is {size('motion.bin')} bytes, expected {motion}")
    if meta.get("microphone", True):
        wav = os.path.join(folder, "audio.wav")
        if not os.path.exists(wav):
            problems.append("no audio.wav")
        else:
            try:
                frames = wav_frames(wav)
            except (wave.Error, EOFError) as error:
                frames = f"an unreadable header ({error})"
            if frames != meta.get("audioFrames", 0):
                problems.append(f"audio.wav has {frames} frames, meta.json says {meta.get('audioFrames', 0)}")
    return problems


def unpack(archive, destination):
    """Unpacks a session's Apple Archive into `destination`, turns audio.caf into audio.wav and
    checks it. The work happens in a folder next to `destination`, moved into place only when
    every check passes, so a failed pull leaves nothing behind. Returns the problems found."""
    parent = os.path.dirname(destination)
    os.makedirs(parent, exist_ok=True)
    work = tempfile.mkdtemp(prefix=f".{os.path.basename(destination)}-", dir=parent)
    try:
        run = subprocess.run(["aa", "extract", "-i", archive, "-d", work], capture_output=True, text=True)
        if run.returncode != 0:
            return [f"aa extract failed: {(run.stderr or run.stdout).strip()}"]
        # The archive came from a player's phone: only plain files at its root are taken
        for name in os.listdir(work):
            path = os.path.join(work, name)
            if os.path.islink(path) or not os.path.isfile(path):
                return [f"the archive holds {name}, which is not a plain file"]
        if not os.path.exists(os.path.join(work, "meta.json")):
            return ["the archive has no meta.json"]
        caf = os.path.join(work, "audio.caf")
        if os.path.exists(caf):
            # Apple Lossless back to 16-bit PCM: the same samples the watch recorded
            run = subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16", caf, os.path.join(work, "audio.wav")],
                                 capture_output=True, text=True)
            if run.returncode != 0:
                return [f"afconvert failed: {(run.stderr or run.stdout).strip()}"]
            os.remove(caf)
        try:
            problems = check(work)
        except (OSError, ValueError) as error:
            problems = [f"could not read meta.json: {error}"]
        if problems:
            return problems
        if os.path.exists(destination):
            # A folder with no meta.json, from an older pull that did not finish
            shutil.rmtree(destination)
        os.rename(work, destination)
        return []
    finally:
        shutil.rmtree(work, ignore_errors=True)


# MARK: - Pull

def pulled(root, sharer, session):
    return os.path.exists(os.path.join(root, sharer, session, "meta.json"))


def apply_deletions(cloudkit, root, dry_run):
    """Deletes the folders the PuttDeletion records name. Returns (records, sharers deleted whole,
    sessions deleted as (sharerID, sessionID))."""
    records = cloudkit.query("PuttDeletion")
    whole, single = set(), set()
    for record in records:
        sharer, session = field(record, "sharerID"), field(record, "sessionID")
        if not sharer or not ID_PATTERN.match(sharer) or (session and not ID_PATTERN.match(session)):
            warn(f"PuttDeletion {record.get('recordName')} has a bad sharer or session ID; skipped")
            continue
        if session:
            single.add((sharer, session))
            target = os.path.join(root, sharer, session)
        else:
            whole.add(sharer)
            target = os.path.join(root, sharer)
        if os.path.exists(target):
            print(f"{'Would delete' if dry_run else 'Deleting'} {os.path.relpath(target, root)}/")
            if not dry_run:
                shutil.rmtree(target)
    return records, whole, single


def pull(args):
    key_path, key_id = os.environ.get("SPOTGOLF_CK_KEY"), os.environ.get("SPOTGOLF_CK_KEY_ID")
    if not key_path:
        fail("set SPOTGOLF_CK_KEY to the path of the server-to-server key's PEM file")
    if not key_id:
        fail("set SPOTGOLF_CK_KEY_ID to the server-to-server key's ID from CloudKit Console")
    key_path = os.path.abspath(os.path.expanduser(key_path))
    if not os.path.exists(key_path):
        fail(f"no key file at {key_path}")
    cloudkit = CloudKit(args.environment, key_path, key_id)
    root = args.to
    print(f"CloudKit {CONTAINER} ({args.environment}) → {root}")
    if not args.dry_run:
        os.makedirs(root, exist_ok=True)

    deletions, whole, single = apply_deletions(cloudkit, root, args.dry_run)
    sessions = cloudkit.query("PuttSession")
    print(f"{len(deletions)} deletion(s), {len(sessions)} session(s) in CloudKit")

    covered, done, new, failed = [], [], 0, 0
    for record in sessions:
        sharer, session = field(record, "sharerID"), field(record, "sessionID")
        name = record.get("recordName")
        if not sharer or not session or not ID_PATTERN.match(sharer) or not ID_PATTERN.match(session):
            warn(f"PuttSession {name} has a bad sharer or session ID; skipped")
            continue
        label = f"{sharer}/{session}"
        if sharer in whole or (sharer, session) in single:
            # The player deleted it, so it is never pulled, and its record goes too
            print(f"  {label}: deleted by the player")
            covered.append(name)
            continue
        if pulled(root, sharer, session):
            print(f"  {label}: already here")
            done.append(name)
            continue
        size = field(record, "size") or (field(record, "archive") or {}).get("size") or 0
        version = field(record, "appVersion") or "?"
        if args.dry_run:
            print(f"  {label}: would download {size / 1e6:.1f} MB (app {version})")
            continue
        print(f"  {label}: downloading {size / 1e6:.1f} MB (app {version})")
        with tempfile.TemporaryDirectory(prefix=".download-", dir=root) as temp:
            archive = os.path.join(temp, "archive.aar")
            try:
                download(field(record, "archive") or {}, archive)
            except (OSError, RuntimeError, urllib.error.URLError) as error:
                warn(f"{label}: download failed: {error}")
                failed += 1
                continue
            problems = unpack(archive, os.path.join(root, sharer, session))
        if problems:
            warn(f"{label}: not kept, its record stays in CloudKit: {'; '.join(problems)}")
            failed += 1
            continue
        done.append(name)
        new += 1

    if args.dry_run:
        if covered:
            print(f"Would delete {len(covered)} PuttSession record(s) the players deleted")
        if done and not args.keep:
            print(f"Would delete {len(done)} PuttSession record(s) already here")
        if deletions:
            print(f"Would delete {len(deletions)} PuttDeletion record(s)")
    else:
        # The deletions go last, so a run that stops early sees them again next time
        to_delete = covered + ([] if args.keep else done)
        if to_delete:
            cloudkit.delete(to_delete)
        if deletions:
            cloudkit.delete([r["recordName"] for r in deletions])
    if not args.dry_run:
        print(f"\nPulled {new} session(s) this run" + (f", {failed} failed" if failed else ""))
    summary(root)


# MARK: - Summary

def read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def drills_finished(drill):
    """Drills not skipped whose 5 tasks all have a Done time."""
    if not drill:
        return 0
    done = Counter(t.get("drill") for t in drill.get("tasks", []) if t.get("done") is not None)
    return sum(1 for d in drill.get("drills", []) if not d.get("skipped") and done[d.get("number")] >= 5)


def summary(root):
    sessions = []
    if os.path.isdir(root):
        for sharer in sorted(os.listdir(root)):
            folder = os.path.join(root, sharer)
            if sharer.startswith(".") or not os.path.isdir(folder):
                continue
            for session in sorted(os.listdir(folder)):
                if not session.startswith(".") and pulled(root, sharer, session):
                    sessions.append((sharer, session, os.path.join(folder, session)))
    sharers = {s for s, _, _ in sessions}
    print(f"\nOn disk: {len(sessions)} session(s) from {len(sharers)} sharer(s)")
    if not sessions:
        return

    counts = {key: Counter() for key in ("putterHead", "putterFace", "grip", "hand")}
    located, statuses = 0, Counter()
    print("\nDrills finished per session")
    for sharer, session, folder in sessions:
        sharing = read_json(os.path.join(folder, "sharing.json")) or {}
        equipment = sharing.get("equipment") or {}
        for key, counter in counts.items():
            counter[equipment.get(key) or "?"] += 1
        if sharing.get("location"):
            located += 1
        else:
            statuses[sharing.get("locationStatus") or "?"] += 1
        print(f"  {sharer}/{session}: {drills_finished(read_json(os.path.join(folder, 'drill.json')))}")

    titles = {"putterHead": "Putter head", "putterFace": "Putter face", "grip": "Grip", "hand": "Hand"}
    for key, counter in counts.items():
        print(f"\n{titles[key]}")
        for value, count in counter.most_common():
            print(f"  {value:<20} {count}")
    others = ", ".join(f"{status} {count}" for status, count in statuses.most_common())
    print(f"\nStarting location: {located} of {len(sessions)}" + (f" (without: {others})" if others else ""))


def path_arg(value):
    """A path argument as an absolute path: ~ expanded, relative to the current directory."""
    return os.path.abspath(os.path.expanduser(value))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--environment", choices=["development", "production"], default="development",
                        help="the CloudKit environment; development by default")
    parser.add_argument("--to", metavar="FOLDER", type=path_arg, default=os.path.join(ROOT, "Data/shared-putts"),
                        help="folder to pull into; Data/shared-putts by default")
    parser.add_argument("--keep", action="store_true", help="keep pulled sessions' records in CloudKit")
    parser.add_argument("--dry-run", action="store_true", help="list what would be deleted and downloaded; change nothing")
    pull(parser.parse_args())


if __name__ == "__main__":
    main()

# README
#
# Environment
#   SPOTGOLF_CK_KEY     Path to the server-to-server key's private key (PEM, EC P-256), kept outside
#                       the repository. Make it with
#                       `openssl ecparam -name prime256v1 -genkey -noout -out <file>` and add its
#                       public key in CloudKit Console, under the container's server-to-server keys
#   SPOTGOLF_CK_KEY_ID  The key ID CloudKit Console shows for that key
#   The key works only on the public database. Development and production each need their own key.
#   Signing uses the cryptography package when it is installed, and openssl otherwise.
#
# Data/shared-putts/<sharerID>/<sessionID>/
#                       One putting session, laid out as a Developer Mode segment, so
#                       analyze-capture.py reads it unchanged
#   meta.json           The segment's details: counts, audio format, start date
#   accel.bin           Accelerometer, 20-byte records (800 Hz)
#   motion.bin          Device motion, 60-byte records (200 Hz)
#   audio.wav           16-bit PCM; converted back from the archive's Apple Lossless audio.caf
#   audio-buffers.csv   When each microphone buffer was captured
#   contacts.csv, candidates.csv, events.csv, marks.csv, locations.csv
#                       As recorded on the watch
#   drill.json          The drills: each drill's Ready time and whether it was skipped, each task's
#                       start (shown) and Done times
#   sharing.json        Session and sharer IDs, app and watch versions, consent version, the
#                       equipment profile and the starting location (or why there is none)
#   A folder is only here once all its checks passed. A sharer ID is not the player's iCloud
#   account; a player who deletes all their data gets a new one.
