import Foundation

/// The wrist's motion before a contact, which tells a putt from nearly everything else on a
/// green: a still address, a backswing, and the wrist back at its address tilt and angle when
/// the ball is hit. Uses only sizes and angles, never a direction in the watch's frame, so it
/// gives the same answer however the watch is worn and for either hand. Fed device motion in
/// batches like `ContactDetector`, which keeps one. See
/// `plans/2026-10-16-bear-dance-putt-analysis.md`.
struct StrokeGate {
    /// Device motion is resampled to this step, so gaps and jitter in the samples don't matter.
    static let step = 0.005
    /// The address is the stillest window this long in [t − `stillFrom`, t − `stillTo`].
    static let stillWindow = 0.4
    static let stillFrom = 3.0
    static let stillTo = 0.5
    /// Mean rotation rate of the address, at most, in rad/s.
    static let maxStill = 0.30
    /// Gravity at the contact is its mean over this long before it.
    static let contactSpan = 0.02
    /// Degrees between gravity at the address and at the contact, at most.
    static let maxTilt = 5.0
    /// The impact axis is the mean rotation over this long before the contact.
    static let impactSpan = 0.04
    /// The backswing's top must be this close before the contact.
    static let topSearch = 1.5
    /// The backswing may start this far before the contact.
    static let lobeSearch = 2.0
    /// Rotation about the impact axis under this, in rad/s, still counts as backswing.
    static let flicker = 0.03
    /// The backswing about the impact axis, in degrees. A chip's is far larger.
    static let minBackswing = 2.5
    static let maxBackswing = 35.0
    /// The contact must come within this of the wrist turning back through its address angle:
    /// that moment minus `earliestReturn` at the earliest, plus `latestReturn` at the latest.
    static let earliestReturn = 0.05
    static let latestReturn = 0.06
    /// Rotation about the impact axis is averaged over this many steps, against gyro noise.
    static let smoothing = 5
    /// Motion after the contact needed to decide it.
    static let lead = earliestReturn + Double(smoothing / 2 + 1) * step

    struct Sample {
        let time: Double
        /// Rotation rate in rad/s.
        let rotation: SIMD3<Double>
        /// Gravity in g.
        let gravity: SIMD3<Double>
    }

    struct Features: Equatable {
        /// Mean rotation rate of the address, rad/s.
        let still: Double
        /// Degrees between gravity at the address and at the contact.
        let tilt: Double
        /// The backswing about the impact axis, in degrees.
        let backswing: Double
        /// The contact's time minus when the wrist turned back through its address angle, or nil
        /// when it had not by `earliestReturn` after the contact.
        let returnOffset: Double?

        var passes: Bool {
            guard let returnOffset else { return false }
            return still <= StrokeGate.maxStill && tilt <= StrokeGate.maxTilt
                && backswing >= StrokeGate.minBackswing && backswing <= StrokeGate.maxBackswing
                && returnOffset >= -StrokeGate.earliestReturn && returnOffset <= StrokeGate.latestReturn
        }
    }

    private var samples: [Sample] = []
    private var head = 0
    /// Samples older than this before the latest are dropped.
    let keep: Double

    init(keep: Double) {
        self.keep = keep
    }

    var latestTime: Double { samples.last?.time ?? -.infinity }

    mutating func add(_ batch: [Sample]) {
        samples += batch
        guard let last = batch.last?.time else { return }
        while head < samples.count, samples[head].time < last - keep { head += 1 }
        if head >= 1024 {
            samples.removeFirst(head)
            head = 0
        }
    }

    /// Whether the motion needed to decide a contact at `time` has arrived.
    func isComplete(at time: Double) -> Bool {
        latestTime >= time + Self.lead
    }

    /// The mean rotation rate over the `span` before `time`, ending `gap` before it.
    func meanRotationRate(before time: Double, span: Double, gap: Double) -> Double {
        var total = 0.0
        var count = 0
        var index = self.index(atOrAfter: time - span)
        while index < samples.count, samples[index].time <= time - gap {
            let r = samples[index].rotation
            total += (r * r).sum().squareRoot()
            count += 1
            index += 1
        }
        return count > 0 ? total / Double(count) : 0
    }

    /// The gate's measures for a contact at `time`, or nil when the motion does not reach far
    /// enough back: the first `stillFrom` seconds of a session.
    func features(at time: Double) -> Features? {
        guard let grid = resample(around: time) else { return nil }
        let step = Self.step
        // Grid index of a time relative to the contact, which sits at index `zero`
        let zero = grid.zero
        func at(_ offset: Double) -> Int { zero + Int((offset / step).rounded()) }

        // Still address: the stillest window, stepping a sample at a time
        let width = Int((Self.stillWindow / step).rounded())
        let first = at(-Self.stillFrom), last = at(-Self.stillTo) - width
        var prefix = [0.0]
        prefix.reserveCapacity(last + width - first + 1)
        for k in first..<(last + width) {
            let r = grid.rotation[k]
            prefix.append(prefix[prefix.count - 1] + (r * r).sum().squareRoot())
        }
        var still = Double.infinity, address = first
        for start in first...last {
            let mean = (prefix[start - first + width] - prefix[start - first]) / Double(width)
            if mean < still {
                still = mean
                address = start
            }
        }

        // Back at address: gravity at the address and at the contact
        let addressGravity = Self.mean(grid.gravity[address..<(address + width)])
        let contactGravity = Self.mean(grid.gravity[at(-Self.contactSpan)...zero])
        let tilt = Self.degrees(between: addressGravity, and: contactGravity)

        // Backswing: rotation about the impact axis, walked back from the contact
        let impact = Self.mean(grid.rotation[at(-Self.impactSpan)...zero])
        let size = (impact * impact).sum().squareRoot()
        let axis = impact / max(size, 1e-9)
        let half = Self.smoothing / 2
        let lobeStart = at(-Self.lobeSearch)
        let end = at(Self.earliestReturn)
        var about = [Double](repeating: 0, count: grid.rotation.count)
        for k in (lobeStart - 1)...end {
            var sum = 0.0
            for j in (k - half)...(k + half) {
                sum += (grid.rotation[j] * axis).sum()
            }
            about[k] = sum / Double(Self.smoothing)
        }
        var top = zero
        let topLimit = at(-Self.topSearch)
        while top >= topLimit, about[top] >= 0 { top -= 1 }
        guard top >= topLimit else {
            return Features(still: still, tilt: tilt, backswing: 0, returnOffset: nil)
        }
        var start = top
        while start > lobeStart, about[start - 1] < Self.flicker { start -= 1 }
        var swing = 0.0
        for k in start...top { swing -= min(about[k], 0) }
        swing *= step

        // Return to address: from the top, turning forward until the backswing is undone
        var returnOffset: Double?
        var turned = 0.0
        for k in (top + 1)...end {
            turned += about[k] * step
            if turned >= swing {
                returnOffset = Double(zero - k) * step
                break
            }
        }
        return Features(still: still, tilt: tilt, backswing: swing * 180 / .pi, returnOffset: returnOffset)
    }

    // MARK: - Pieces

    private struct Grid {
        var rotation: [SIMD3<Double>]
        var gravity: [SIMD3<Double>]
        /// The index of the contact's time.
        let zero: Int
    }

    /// The motion from `stillFrom` before `time` to `lead` after it, linearly interpolated onto
    /// a `step` grid that has the contact on a grid point. Nil when the samples don't cover it.
    private func resample(around time: Double) -> Grid? {
        let before = Int((Self.stillFrom / Self.step).rounded())
        let after = Int((Self.earliestReturn / Self.step).rounded()) + Self.smoothing / 2
        let from = time - Double(before) * Self.step, to = time + Double(after) * Self.step
        guard head < samples.count, samples[head].time <= from + Self.step, latestTime >= to else { return nil }
        let count = before + after + 1
        var rotation: [SIMD3<Double>] = []
        var gravity: [SIMD3<Double>] = []
        rotation.reserveCapacity(count)
        gravity.reserveCapacity(count)
        var next = max(index(atOrAfter: from), head + 1)
        for k in 0..<count {
            let t = from + Double(k) * Self.step
            while next < samples.count - 1, samples[next].time < t { next += 1 }
            let a = samples[next - 1], b = samples[next]
            let span = b.time - a.time
            let f = span > 0 ? min(max((t - a.time) / span, 0), 1) : 0
            rotation.append(a.rotation + (b.rotation - a.rotation) * f)
            gravity.append(a.gravity + (b.gravity - a.gravity) * f)
        }
        return Grid(rotation: rotation, gravity: gravity, zero: before)
    }

    /// The first sample at or after `time`.
    private func index(atOrAfter time: Double) -> Int {
        var low = head, high = samples.count
        while low < high {
            let middle = (low + high) / 2
            if samples[middle].time < time { low = middle + 1 } else { high = middle }
        }
        return low
    }

    private static func mean(_ vectors: ArraySlice<SIMD3<Double>>) -> SIMD3<Double> {
        vectors.reduce(SIMD3<Double>(), +) / Double(max(vectors.count, 1))
    }

    private static func degrees(between a: SIMD3<Double>, and b: SIMD3<Double>) -> Double {
        let lengths = ((a * a).sum() * (b * b).sum()).squareRoot()
        guard lengths > 0 else { return 180 }
        return acos(min(max((a * b).sum() / lengths, -1), 1)) * 180 / .pi
    }
}
