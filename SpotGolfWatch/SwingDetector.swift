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
    // Logged once per start and restart, to show that accelerometer data arrives at all
    private var hasReceivedBatch = false
    // Updates can end on an error or stop with no error, so they are restarted
    private var watchdog = RestartWatchdog(startedAt: Date(), checksData: true)
    private var watchdogTimer: Timer?

    /// Called with each swing once its peak force is known.
    var onSwing: ((StrokeSuggestion) -> Void)?

    func start() {
        guard !isRunning else { return }
        guard CMBatchedSensorManager.isAccelerometerSupported else {
            Log.swings.error("Swing detection off: batched accelerometer not supported on this watch")
            return
        }
        isRunning = true
        Log.swings.notice("Swing detection started")
        finder = SwingPeakFinder()
        startUpdates()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: RestartWatchdog.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkUpdates() }
        }
    }

    func stop() {
        guard isRunning else { return }
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        manager.stopAccelerometerUpdates()
        isRunning = false
        Log.swings.notice("Swing detection stopped")
        // A swing still waiting for its peak window to close
        if let swing = finder.flush() {
            Log.swings.notice("Swing at \(swing.timestamp, privacy: .public), peak \(swing.peakG ?? 0, privacy: .public) g (on stop)")
            onSwing?(swing)
        }
    }

    private func startUpdates() {
        watchdog.started(at: Date())
        hasReceivedBatch = false
        manager.startAccelerometerUpdates { [weak self] batch, error in
            if let error {
                Log.swings.error("Accelerometer error: \(String(describing: error), privacy: .public)")
                Task { @MainActor in self?.updatesFailed() }
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
                self.watchdog.dataReceived(at: Date())
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

    /// An error may have ended updates. A start that keeps failing is left to the watchdog.
    private func updatesFailed() {
        guard isRunning else { return }
        guard watchdog.shouldRestartAfterError(at: Date()) else {
            Log.swings.error("Accelerometer error within \(RestartWatchdog.interval, privacy: .public) s of a start; leaving the restart to the watchdog")
            return
        }
        Log.swings.notice("Restarting the accelerometer after an error")
        restartUpdates()
    }

    private func checkUpdates() {
        guard isRunning, watchdog.shouldRestart(at: Date(), isActive: manager.isAccelerometerActive) else { return }
        Log.swings.error("Accelerometer stopped sending data (active \(self.manager.isAccelerometerActive, privacy: .public)); restarting")
        restartUpdates()
    }

    private func restartUpdates() {
        manager.stopAccelerometerUpdates()
        startUpdates()
    }
}
