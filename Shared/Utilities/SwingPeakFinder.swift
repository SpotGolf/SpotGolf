import Foundation

/// Finds swings in accelerometer readings: a reading of `threshold` g or more starts a swing,
/// the highest reading within `peakWindow` is its peak force, and readings within `cooldown`
/// of the start belong to the same swing.
struct SwingPeakFinder {
    /// Low enough for chips and putts. Swings while walking are dropped later by `StrokeFinder`.
    static let threshold: Double = 3 // g
    static let peakWindow: TimeInterval = 0.5
    static let cooldown: TimeInterval = 3

    struct Reading {
        let timestamp: Date
        /// Total force in g: √(x² + y² + z²).
        let magnitude: Double
    }

    // A swing whose peak window has not closed yet
    private var current: (timestamp: Date, peakG: Float)?
    // The latest swing started, for the cooldown
    private var lastStart: Date?

    /// Adds a batch of readings in time order. Returns the swings whose peak window closed.
    mutating func add(_ readings: [Reading]) -> [StrokeSuggestion] {
        var found: [StrokeSuggestion] = []
        for reading in readings {
            if let swing = current, reading.timestamp.timeIntervalSince(swing.timestamp) > Self.peakWindow {
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
            if let lastStart, reading.timestamp.timeIntervalSince(lastStart) < Self.cooldown {
                continue
            }
            current = (reading.timestamp, Float(reading.magnitude))
            lastStart = reading.timestamp
        }
        return found
    }

    /// Returns the swing whose peak window has not closed yet, if any, with the highest force
    /// so far. Used when readings stop, so that swing is not lost.
    mutating func flush() -> StrokeSuggestion? {
        guard let swing = current else { return nil }
        current = nil
        return .swing(at: swing.timestamp, peakG: swing.peakG)
    }
}
