import CoreMotion
import Foundation
import os

/// Detects swings from batches of wrist accelerometer readings. `CMBatchedSensorManager`
/// delivers them about once a second, and only during a workout, which a round always has.
@MainActor
final class SwingDetector {
    private let manager = CMBatchedSensorManager()
    private var finder = SwingPeakFinder()
    private var isRunning = false
    // Logged once per start, to show that accelerometer data arrives at all
    private var hasReceivedBatch = false

    /// Called with each swing once its peak force is known.
    var onSwing: ((StrokeSuggestion) -> Void)?

    func start() {
        guard !isRunning else { return }
        guard CMBatchedSensorManager.isAccelerometerSupported else {
            Log.swings.error("Swing detection off: batched accelerometer not supported on this watch")
            return
        }
        isRunning = true
        hasReceivedBatch = false
        Log.swings.notice("Swing detection started")
        finder = SwingPeakFinder()
        manager.startAccelerometerUpdates { [weak self] batch, error in
            if let error {
                Log.swings.error("Accelerometer error, swing detection stopped: \(String(describing: error), privacy: .public)")
                // Lets the next start() try again
                Task { @MainActor in self?.stop() }
            }
            guard let batch else { return }
            // Reading timestamps count from boot
            let bootDate = Date(timeIntervalSinceNow: -ProcessInfo.processInfo.systemUptime)
            let readings = batch.map { data in
                let a = data.acceleration
                return SwingPeakFinder.Reading(timestamp: bootDate.addingTimeInterval(data.timestamp),
                                               magnitude: (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot())
            }
            Task { @MainActor in
                guard let self else { return }
                if !self.hasReceivedBatch {
                    self.hasReceivedBatch = true
                    Log.swings.notice("First accelerometer batch received: \(readings.count, privacy: .public) readings")
                }
                for swing in self.finder.add(readings) {
                    Log.swings.notice("Swing at \(swing.timestamp, privacy: .public), peak \(swing.peakG ?? 0, privacy: .public) g")
                    self.onSwing?(swing)
                }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        manager.stopAccelerometerUpdates()
        isRunning = false
        Log.swings.notice("Swing detection stopped")
    }
}
