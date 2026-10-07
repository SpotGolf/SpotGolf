import Foundation

/// Finds ball contact in the watch's sensor streams: an accelerometer burst and a microphone
/// click at the same instant, with an instant attack, while the wrist is turning. Pure
/// arithmetic over the samples, fed in batches as they arrive, so the same code runs on the
/// watch and in a replay of a Putt Lab capture. See `plans/2026-10-06-putt-detection.md`.
///
/// Times are seconds on one clock: the watch uses uptime, which `CMAccelerometerData` and
/// `AVAudioTime.hostTime` share; a replay uses seconds since its capture started.
struct ContactDetector {
    /// Readings on each side of a reading that make its moving mean (11 ms at 800 Hz).
    static let burstHalfWindow = 4
    /// A reading with a smaller burst is not a candidate.
    static let minBurst = 0.05
    /// The background is the median level over this long.
    static let backgroundWindow = 10.0
    /// The click is the loudest millisecond this close to the reading.
    static let clickWindow = 0.004
    /// The click must be this many times the loudest level 2 to 6 ms before it.
    static let minOnset = 4.0
    static let onsetGap = 0.002
    static let onsetSpan = 0.006
    /// The wrist must turn this fast on average over `turningWindow` before the reading.
    static let minTurning = 0.4
    static let turningWindow = 0.1
    /// A contact scores at least this much; the phone draws the lines above it.
    static let minRecordedScore = 1.2
    /// Candidates this close together are one stroke: the strongest is the contact.
    static let contactSpacing = 1.0
    /// A candidate whose audio or rotation has not arrived this long after the reading is dropped.
    static let maxWait = 3.0
    /// The background is worked out again after this long; it barely changes faster.
    static let backgroundRefresh = 2.0

    struct Reading {
        let time: Double
        let x: Double
        let y: Double
        let z: Double
    }

    struct Rotation {
        let time: Double
        /// The rotation rate's size in rad/s.
        let rate: Double
    }

    struct Contact: Equatable {
        let time: Double
        let score: Double
        let burst: Double
        let click: Double
        let turning: Double
    }

    private struct Candidate {
        let time: Double
        let burst: Double
    }

    // Audio levels per millisecond, oldest first
    private var levels: [(time: Double, level: Double)] = []
    private var lastSample: Float = 0
    // A millisecond cut by a buffer's end
    private var partial: (start: Double, sumSquares: Double, count: Int)?
    private var latestAudioTime = -Double.infinity

    private var rotations: [Rotation] = []
    private var latestRotationTime = -Double.infinity

    // The last readings of the previous batch, so the moving mean spans batches
    private var carry: [Reading] = []
    private var candidates: [Candidate] = []
    private var latestReadingTime = -Double.infinity
    private var cachedBackground: (until: Double, value: Double?)?

    /// Candidates still waiting for their audio or rotation. For tests.
    var pendingCandidates: Int { candidates.count }

    // The stroke being scored: its first candidate's time and the best contact so far
    private var open: (start: Double, best: Contact)?

    init() {}

    // MARK: - Input

    /// Audio samples from one buffer, in full-scale units; `startTime` is the first sample's.
    mutating func addAudio(_ samples: [Float], startTime: Double, sampleRate: Double) {
        let step = max(1, Int((sampleRate / 1000).rounded()))
        var start = partial?.start ?? startTime
        var sumSquares = partial?.sumSquares ?? 0
        var count = partial?.count ?? 0
        for (index, sample) in samples.enumerated() {
            if count == 0 {
                start = startTime + Double(index) / sampleRate
            }
            let difference = Double(sample - lastSample)
            lastSample = sample
            sumSquares += difference * difference
            count += 1
            if count == step {
                levels.append((start, (sumSquares / Double(step)).squareRoot()))
                sumSquares = 0
                count = 0
            }
        }
        partial = count > 0 ? (start, sumSquares, count) : nil
        latestAudioTime = startTime + Double(samples.count) / sampleRate
        trimLevels()
    }

    mutating func addRotations(_ batch: [Rotation]) {
        rotations += batch
        if let last = batch.last?.time {
            latestRotationTime = max(latestRotationTime, last)
            let keepFrom = last - Self.turningWindow - 1
            if let first = rotations.firstIndex(where: { $0.time >= keepFrom }), first > 0 {
                rotations.removeFirst(first)
            }
        }
    }

    /// Accelerometer readings in time order, in g.
    mutating func addReadings(_ batch: [Reading]) {
        let half = Self.burstHalfWindow
        let width = 2 * half + 1
        let all = carry + batch
        if all.count >= width {
            var sumX = 0.0, sumY = 0.0, sumZ = 0.0
            for k in 0..<width {
                sumX += all[k].x
                sumY += all[k].y
                sumZ += all[k].z
            }
            for k in half..<(all.count - half) {
                if k > half {
                    let added = all[k + half], dropped = all[k - half - 1]
                    sumX += added.x - dropped.x
                    sumY += added.y - dropped.y
                    sumZ += added.z - dropped.z
                }
                let reading = all[k]
                let bx = reading.x - sumX / Double(width)
                let by = reading.y - sumY / Double(width)
                let bz = reading.z - sumZ / Double(width)
                let burst = (bx * bx + by * by + bz * bz).squareRoot()
                if burst >= Self.minBurst {
                    candidates.append(Candidate(time: reading.time, burst: burst))
                }
            }
        }
        carry = Array(all.suffix(2 * half))
        if let last = batch.last?.time {
            latestReadingTime = max(latestReadingTime, last)
        }
    }

    // MARK: - Output

    /// Scores the candidates whose audio and rotation have arrived, and returns the contacts
    /// of strokes that are over. Call after each batch.
    mutating func evaluate() -> [Contact] {
        let complete = min(latestAudioTime - Self.clickWindow - 0.001, latestRotationTime)
        guard !candidates.isEmpty else { return closeOpen(before: complete) }
        let background = self.background(until: complete)
        var found: [Contact] = []
        var remaining: [Candidate] = []
        for candidate in candidates {
            if candidate.time > complete {
                // Still waiting for audio or rotation; given up on when neither comes
                if latestReadingTime - candidate.time < Self.maxWait { remaining.append(candidate) }
                continue
            }
            guard let background, let (click, onset) = click(at: candidate.time, background: background) else { continue }
            guard onset >= Self.minOnset else { continue }
            let turning = turning(before: candidate.time)
            guard turning >= Self.minTurning else { continue }
            let score = candidate.burst * click
            guard score >= Self.minRecordedScore else { continue }
            let contact = Contact(time: candidate.time, score: score, burst: candidate.burst, click: click, turning: turning)
            if let current = open, candidate.time - current.start <= Self.contactSpacing {
                if score > current.best.score { open = (current.start, contact) }
            } else {
                if let current = open { found.append(current.best) }
                open = (candidate.time, contact)
            }
        }
        candidates = remaining
        return found + closeOpen(before: complete)
    }

    /// The contact of a stroke still being scored, at the end of the stream.
    mutating func flush() -> [Contact] {
        defer { open = nil }
        return open.map { [$0.best] } ?? []
    }

    // MARK: - Pieces

    private mutating func closeOpen(before time: Double) -> [Contact] {
        guard let current = open, time - current.start > Self.contactSpacing else { return [] }
        open = nil
        return [current.best]
    }

    private mutating func trimLevels() {
        guard let last = levels.last?.time else { return }
        let keepFrom = last - Self.backgroundWindow - 1
        if let first = levels.firstIndex(where: { $0.time >= keepFrom }), first > 0 {
            levels.removeFirst(first)
        }
    }

    /// The median level over `backgroundWindow` before `time`, or nil with under a second of
    /// audio. Kept for `backgroundRefresh`, since sorting 10 s of levels every batch is wasted work.
    private mutating func background(until time: Double) -> Double? {
        if let cached = cachedBackground, cached.value != nil, time - cached.until < Self.backgroundRefresh {
            return cached.value
        }
        let window = levels.lazy.filter { $0.time >= time - Self.backgroundWindow && $0.time < time }.map(\.level)
        let sorted = Array(window).sorted()
        let value = sorted.count >= 1000 ? sorted[sorted.count / 2] : nil
        cachedBackground = (time, value)
        return value
    }

    /// The loudest millisecond within `clickWindow` of `time` as a multiple of `background`, and
    /// its onset: that level over the loudest 2 to 6 ms before it.
    private func click(at time: Double, background: Double) -> (click: Double, onset: Double)? {
        let first = levels.partitionIndex { $0.time >= time - Self.clickWindow }
        var loudest: (index: Int, level: Double)?
        var index = first
        while index < levels.count, levels[index].time <= time + Self.clickWindow {
            if loudest == nil || levels[index].level > loudest!.level {
                loudest = (index, levels[index].level)
            }
            index += 1
        }
        guard let loudest, background > 0 else { return nil }
        let peakTime = levels[loudest.index].time
        var earlier = background
        var back = loudest.index - 1
        while back >= 0, levels[back].time >= peakTime - Self.onsetSpan {
            if levels[back].time <= peakTime - Self.onsetGap {
                earlier = max(earlier, levels[back].level)
            }
            back -= 1
        }
        return (loudest.level / background, loudest.level / earlier)
    }

    /// The mean rotation rate over `turningWindow` before `time`, ending 10 ms before it.
    private func turning(before time: Double) -> Double {
        var total = 0.0
        var count = 0
        for rotation in rotations where rotation.time >= time - Self.turningWindow && rotation.time <= time - 0.01 {
            total += rotation.rate
            count += 1
        }
        return count > 0 ? total / Double(count) : 0
    }
}

private extension Array {
    /// The first index whose element satisfies `belongsInSecondPartition`, for a sorted array.
    func partitionIndex(where belongsInSecondPartition: (Element) -> Bool) -> Int {
        var low = 0
        var high = count
        while low < high {
            let middle = (low + high) / 2
            if belongsInSecondPartition(self[middle]) { high = middle } else { low = middle + 1 }
        }
        return low
    }
}
