import Foundation

/// Finds swings in accelerometer readings: a reading of `threshold` g or more starts a swing,
/// the highest reading within `peakWindow` is its peak force, and readings within `cooldown`
/// of the start belong to the same swing.
struct SwingPeakFinder {
    static let threshold: Double = 10 // g
    static let peakWindow: TimeInterval = 0.5
    static let cooldown: TimeInterval = 3

    struct Reading {
        let timestamp: Date
        /// Total force in g: √(x² + y² + z²).
        let magnitude: Double
    }

    // A swing whose peak window has not closed yet
    private var current: Swing?
    // The latest swing started, for the cooldown
    private var lastStart: Date?

    /// Adds a batch of readings in time order. Returns the swings whose peak window closed.
    mutating func add(_ readings: [Reading]) -> [Swing] {
        var found: [Swing] = []
        for reading in readings {
            if let swing = current, reading.timestamp.timeIntervalSince(swing.timestamp) > Self.peakWindow {
                found.append(swing)
                current = nil
            }
            if let swing = current {
                if reading.magnitude > Double(swing.peakG) {
                    current = Swing(timestamp: swing.timestamp, peakG: Float(reading.magnitude))
                }
                continue
            }
            guard reading.magnitude >= Self.threshold else { continue }
            if let lastStart, reading.timestamp.timeIntervalSince(lastStart) < Self.cooldown {
                continue
            }
            current = Swing(timestamp: reading.timestamp, peakG: Float(reading.magnitude))
            lastStart = reading.timestamp
        }
        return found
    }
}
