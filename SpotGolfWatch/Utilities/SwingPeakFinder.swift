import Foundation

/// Finds swings in accelerometer readings: a reading of `threshold` g or more starts a swing,
/// readings within `cooldown` of its start belong to it, and the highest of them is its peak force.
struct SwingPeakFinder {
    /// Low enough for chips and putts. Swings while walking are dropped later by `StrokeFinder`.
    static let threshold: Double = 3 // g
    /// Readings this long after a swing's first high reading are part of it, and its peak is the
    /// highest of them all. So a waggle that starts the swing does not hide the real swing a
    /// second or two behind it, which `StrokeFinder` needs to tell a shot from a fidget.
    static let cooldown: TimeInterval = 3

    struct Reading {
        let timestamp: Date
        /// Total force in g: √(x² + y² + z²).
        let magnitude: Double
    }

    // The swing whose cooldown has not ended yet
    private var current: (timestamp: Date, peakG: Float)?

    /// Adds a batch of readings in time order. Returns the swings whose cooldown ended.
    mutating func add(_ readings: [Reading]) -> [StrokeSuggestion] {
        var found: [StrokeSuggestion] = []
        for reading in readings {
            if let swing = current, reading.timestamp.timeIntervalSince(swing.timestamp) > Self.cooldown {
                found.append(.swing(at: swing.timestamp, peakG: swing.peakG))
                current = nil
            }
            if let swing = current {
                if reading.magnitude > Double(swing.peakG) {
                    current = (swing.timestamp, Float(reading.magnitude))
                }
                continue
            }
            guard reading.magnitude >= Self.threshold else { continue }
            current = (reading.timestamp, Float(reading.magnitude))
        }
        return found
    }

    /// Returns the swing whose cooldown has not ended yet, if any, with the highest force so far.
    /// Used when readings stop, so that swing is not lost.
    mutating func flush() -> StrokeSuggestion? {
        guard let swing = current else { return nil }
        current = nil
        return .swing(at: swing.timestamp, peakG: swing.peakG)
    }
}
