import CoreMotion
import Foundation

/// Detects swings from batches of wrist accelerometer readings. `CMBatchedSensorManager`
/// delivers them about once a second, and only during a workout, which a round always has.
@MainActor
final class SwingDetector {
    private let manager = CMBatchedSensorManager()
    private var finder = SwingPeakFinder()
    private var isRunning = false

    /// Called with each swing once its peak force is known.
    var onSwing: ((Swing) -> Void)?

    func start() {
        guard !isRunning, CMBatchedSensorManager.isAccelerometerSupported else { return }
        isRunning = true
        finder = SwingPeakFinder()
        manager.startAccelerometerUpdates { [weak self] batch, error in
            if let error {
                print("SwingDetector: accelerometer error – \(error)")
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
                for swing in self.finder.add(readings) {
                    self.onSwing?(swing)
                }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        manager.stopAccelerometerUpdates()
        isRunning = false
    }
}
