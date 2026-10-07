#!/usr/bin/env python3
"""Summarizes a putt capture from the watch's Putt Lab page.

    ./analyze-capture.py <capture.zip or folder> [--window 5] [--after 1] [--events]

Prints the capture's details and the real sample rates, then one row per mark for the
stroke before it. The window runs from --window seconds before the mark (but after the
previous mark's tap) to --after seconds before it, so the taps on the watch are left out.
Each row gives the strongest accelerometer reading and rotation rate, and the contact
score: ball contact is a click and a high-frequency accelerometer burst at the same
instant, so the score is the largest product, over the window, of the burst (each axis
minus its 11 ms moving mean, in g) and the click (1 ms RMS of the high-passed audio,
as a multiple of the capture's background). High-passing the audio takes out wind.
Two gates keep out what is not a stroke hitting something: the click must rise sharply
(at least 4 times what it was 2 to 6 ms earlier, where a scrape on grass or a putter set
down rises slowly) and the wrist must be moving (rotation rate of 0.4 rad/s or more in
the 100 ms before). The "loose" column is the score without the gates.
With --events, also lists the peaks away from any mark. Pure Python; no numpy.
See plans/2026-10-06-putt-capture.md for the file layout and findings.
"""
import argparse
import bisect
import json
import math
import os
import statistics
import struct
import tempfile
import wave
import zipfile


def load_folder(path):
    if zipfile.is_zipfile(path):
        folder = tempfile.mkdtemp(prefix="putt-capture-")
        with zipfile.ZipFile(path) as z:
            z.extractall(folder)
        # The zip may hold the capture folder itself
        entries = [e for e in os.listdir(folder) if not e.startswith("_")]
        if len(entries) == 1 and os.path.isdir(os.path.join(folder, entries[0])):
            folder = os.path.join(folder, entries[0])
        return folder
    return path


def read_records(path, fmt):
    size = struct.calcsize(fmt)
    if not os.path.exists(path):
        return []
    with open(path, "rb") as f:
        data = f.read()
    data = data[: len(data) - len(data) % size]
    return list(struct.iter_unpack(fmt, data))


def read_audio(path):
    """Returns (samples, rate, channels); samples are the first channel's, as ints."""
    if not os.path.exists(path):
        return None, 0, 0
    with wave.open(path, "rb") as w:
        rate, channels, width, frames = w.getframerate(), w.getnchannels(), w.getsampwidth(), w.getnframes()
        raw = w.readframes(frames)
    if width != 2:
        print(f"audio: unexpected sample width {width}")
        return None, rate, channels
    samples = struct.unpack(f"<{len(raw) // 2}h", raw)
    if channels > 1:
        samples = samples[::channels]
    return samples, rate, channels


def read_marks(folder, meta):
    marks = list(meta.get("marks", []))
    path = os.path.join(folder, "marks.csv")
    if not marks and os.path.exists(path):
        with open(path) as f:
            next(f, None)
            for line in f:
                t, label, date = line.strip().split(",", 2)
                marks.append({"t": float(t), "label": label, "date": date})
    return marks


def rate(records):
    if len(records) < 2:
        return 0
    return (len(records) - 1) / (records[-1][0] - records[0][0])


def clicks(samples, audio):
    """(t, rms) per millisecond of the high-passed audio (each sample minus the one before,
    which cuts wind and voices and keeps clicks), rms in full-scale units."""
    if not samples or not audio:
        return []
    step = max(1, int(audio["sampleRate"] / 1000))
    t0 = audio["startTime"]
    rows = []
    for i in range(1, len(samples) - step, step):
        total = 0
        for k in range(i, i + step):
            d = samples[k] - samples[k - 1]
            total += d * d
        rows.append((t0 + i / audio["sampleRate"], math.sqrt(total / step) / 32768))
    return rows


def bursts(accel, half=4):
    """(t, g) per accelerometer reading: the magnitude of each axis minus its moving mean over
    2 * half + 1 readings, which keeps the ring of an impact and drops the swing itself."""
    n = len(accel)
    width = 2 * half + 1
    if n < width:
        return []
    sums = [sum(accel[k][i] for k in range(width)) for i in (1, 2, 3)]
    rows = [(accel[k][0], 0.0) for k in range(half)]
    for k in range(half, n - half):
        if k > half:
            for i in (1, 2, 3):
                sums[i - 1] += accel[k + half][i] - accel[k - half - 1][i]
        rows.append((accel[k][0], math.sqrt(sum((accel[k][i] - sums[i - 1] / width) ** 2 for i in (1, 2, 3)))))
    rows += [(accel[k][0], 0.0) for k in range(n - half, n)]
    return rows


def peak(records, times, start, end, value):
    """(t, value) of the largest `value` among records with start <= t <= end, or None."""
    i, j = bisect.bisect_left(times, start), bisect.bisect_right(times, end)
    best = None
    for r in records[i:j]:
        v = value(r)
        if best is None or v > best[1]:
            best = (r[0], v)
    return best


def events(records, value, threshold, gap=1.0):
    """Times where `value` first crosses `threshold`, at least `gap` seconds apart, with the peak until the next gap."""
    found = []
    current = None
    for r in records:
        v = value(r)
        if current and r[0] - current[0] > gap:
            found.append(current)
            current = None
        if current:
            if v > current[1]:
                current = (current[0], v)
        elif v >= threshold:
            current = (r[0], v)
    if current:
        found.append(current)
    return found


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("capture")
    parser.add_argument("--window", type=float, default=5, help="longest window before a mark to look in")
    parser.add_argument("--after", type=float, default=1, help="seconds before the mark the window ends, to skip the tap")
    parser.add_argument("--events", action="store_true", help="list peaks away from any mark")
    args = parser.parse_args()

    folder = load_folder(args.capture)
    with open(os.path.join(folder, "meta.json")) as f:
        meta = json.load(f)
    accel = read_records(os.path.join(folder, "accel.bin"), "<dfff")
    motion = read_records(os.path.join(folder, "motion.bin"), "<d13f")
    samples, audio_rate, channels = read_audio(os.path.join(folder, "audio.wav"))
    marks = read_marks(folder, meta)
    audio = meta.get("audio")
    burst = bursts(accel)
    click = clicks(samples, audio)
    background = statistics.median(e for _, e in click[::7]) if click else 0
    times = {id(x): [r[0] for r in x] for x in (accel, motion, burst, click)}

    print(f"capture {meta['id']}" + ("" if meta.get("savesData", True) else
          f"  (battery test, mic {'on' if meta.get('microphone', True) else 'off'})"))
    print(f"  start {meta['startDate']}  duration {meta.get('duration', 0):.1f} s")
    print(f"  accel  {len(accel):>8} samples  {rate(accel):6.1f} Hz")
    print(f"  motion {len(motion):>8} samples  {rate(motion):6.1f} Hz")
    if samples:
        print(f"  audio  {len(samples):>8} frames   {audio_rate} Hz, {channels} ch, {len(samples) / audio_rate:.1f} s"
              f" starting at {audio['startTime']:.3f} s (host-uptime gap {audio['startUptime'] - audio['startHostTime']:+.4f} s),"
              f" high-passed background {background:.6f}")
    else:
        print("  audio  none")
    print(f"  marks  {len(marks)}: " + ", ".join(f"{m['label']}@{m['t']:.1f}" for m in marks))

    g = lambda r: math.sqrt(r[1] ** 2 + r[2] ** 2 + r[3] ** 2)
    rot = lambda r: math.sqrt(r[1] ** 2 + r[2] ** 2 + r[3] ** 2)
    second = lambda r: r[1]

    def cell(p, f):
        return f"{p[1]:{f}} {p[0]:7.2f}" if p else f"{'-':>8} {'':>7}"

    def click_near(t):
        """The loudest click within 4 ms of `t` as a multiple of the background, and its onset:
        how many times louder it is than the loudest millisecond 2 to 6 ms before it."""
        i, j = bisect.bisect_left(times[id(click)], t - 0.004), bisect.bisect_right(times[id(click)], t + 0.004)
        if j <= i or not background:
            return 0, 0
        k = max(range(i, j), key=lambda q: click[q][1])
        earlier = max(max((e for _, e in click[max(0, k - 6):max(0, k - 2)]), default=background), background)
        return click[k][1] / background, click[k][1] / earlier

    def rotation_before(t):
        """Mean rotation rate over the 100 ms before `t`."""
        i, j = bisect.bisect_left(times[id(motion)], t - 0.1), bisect.bisect_right(times[id(motion)], t - 0.01)
        return statistics.mean(rot(r) for r in motion[i:j]) if j > i else 0

    print()
    print(f"{'mark':>5} {'label':>9} {'t':>7} | {'accel g':>8} {'at':>7} | {'rot rad/s':>9} {'at':>7} | {'burst g':>8} {'click/bg':>8}"
          f" | {'score':>7} {'burst':>6} {'click':>6} {'onset':>6} {'rot':>5} {'at':>7} | {'loose':>7}")
    rows = []
    previous = 2.5
    for i, m in enumerate(marks, 1):
        start, end = max(previous, m["t"] - args.window), m["t"] - args.after
        previous = m["t"] + 0.8
        a = peak(accel, times[id(accel)], start, end, g)
        r = peak(motion, times[id(motion)], start, end, rot)
        b = peak(burst, times[id(burst)], start, end, second)
        c = peak(click, times[id(click)], start, end, second)
        best = (0.0, 0.0, 0.0, 0.0, 0.0, start)
        loose = 0.0
        if click:
            lo, hi = bisect.bisect_left(times[id(burst)], start), bisect.bisect_right(times[id(burst)], end)
            for t, v in burst[lo:hi]:
                if v < 0.05:
                    continue
                e, onset = click_near(t)
                loose = max(loose, v * e)
                if onset < 4:
                    continue
                turning = rotation_before(t)
                if turning < 0.4:
                    continue
                if v * e > best[0]:
                    best = (v * e, v, e, onset, turning, t)
        rows.append((m["label"], a, r, b, c, best, loose))
        print(f"{i:>5} {m['label']:>9} {m['t']:7.2f} | {cell(a, '8.2f')} | {cell(r, '9.2f')} | {b[1] if b else 0:8.3f}"
              f" {c[1] / background if c and background else 0:8.1f} | {best[0]:7.2f} {best[1]:6.3f} {best[2]:6.1f} {best[3]:6.1f}"
              f" {best[4]:5.2f} {best[5] - m['t']:+7.2f} | {loose:7.2f}")

    print()
    for label in sorted({row[0] for row in rows}):
        selected = [row for row in rows if row[0] == label]
        print(f"{label} (n={len(selected)}): median (min to max)")
        for name, value, fmt in [("accel g", lambda row: row[1] and row[1][1], ".2f"),
                                 ("rot rad/s", lambda row: row[2] and row[2][1], ".2f"),
                                 ("burst g", lambda row: row[3] and row[3][1], ".3f"),
                                 ("click/bg", lambda row: row[4] and background and row[4][1] / background, ".1f"),
                                 ("score", lambda row: row[5][0], ".2f"),
                                 ("loose", lambda row: row[6], ".2f")]:
            values = sorted(v for v in map(value, selected) if v)
            if values:
                print(f"   {name:>9}: {statistics.median(values):{fmt}} ({values[0]:{fmt}} to {values[-1]:{fmt}})")
        print("       scores: " + " ".join(f"{v:.1f}" for v in sorted(row[5][0] for row in selected)))

    if args.events:
        near = lambda t: any(m["t"] - args.window <= t <= m["t"] for m in marks)
        print()
        print("accelerometer peaks of 2 g or more away from marks:")
        for t, v in events(accel, g, 2):
            if not near(t):
                print(f"  {t:8.2f} s  {v:5.2f} g")
        print("bursts of 0.25 g or more away from marks:")
        for t, v in events(burst, second, 0.25, gap=0.5):
            if not near(t):
                print(f"  {t:8.2f} s  {v:5.3f}")
        print("rotation peaks of 3 rad/s or more away from marks:")
        for t, v in events(motion, rot, 3):
            if not near(t):
                print(f"  {t:8.2f} s  {v:5.2f} rad/s")
        if click:
            print("clicks of 50 times the background or more away from marks:")
            for t, v in events(click, second, 50 * background, gap=0.5):
                if not near(t):
                    print(f"  {t:8.2f} s  {v / background:6.1f}")


if __name__ == "__main__":
    main()
