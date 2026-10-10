import CoreMotion
import Foundation
import os

/// Detects swings from the wrist accelerometer batches `SensorInputs` delivers, about once a
/// second and only during a workout, which a round always has.
@MainActor
final class SwingDetector {
    private let sensors: SensorInputs
    private var finder = SwingPeakFinder()
    private var subscription: SensorInputs.Subscription?

    /// Called with each swing once its peak force is known.
    var onSwing: ((StrokeSuggestion) -> Void)?

    /// Called with each start and stop, for the round's stream.
    var onEvent: ((StreamEvent) -> Void)?

    init(sensors: SensorInputs) {
        self.sensors = sensors
    }

    var isRunning: Bool { subscription != nil }

    func start() {
        guard subscription == nil else { return }
        Log.swings.notice("Swing detection started")
        onEvent?(StreamEvent(code: .swingDetectionStarted))
        finder = SwingPeakFinder()
        let taps = sensors.taps
        subscription = sensors.subscribeAccelerometer { [weak self] batch in
            let readings = batch.compactMap { data -> SwingPeakFinder.Reading? in
                guard !taps.covers(uptime: data.timestamp) else { return nil }
                let a = data.acceleration
                return SwingPeakFinder.Reading(timestamp: Uptime.date(at: data.timestamp),
                                               magnitude: (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot())
            }
            Task { @MainActor in
                guard let self, self.subscription != nil else { return }
                for swing in self.finder.add(readings) {
                    Log.swings.notice("Swing at \(swing.timestamp), peak \(swing.peakG ?? 0) g")
                    self.onSwing?(swing)
                }
            }
        }
    }

    func stop() {
        guard let subscription else { return }
        subscription.cancel()
        self.subscription = nil
        Log.swings.notice("Swing detection stopped")
        onEvent?(StreamEvent(code: .swingDetectionStopped))
        // A swing still waiting for its peak window to close
        if let swing = finder.flush() {
            Log.swings.notice("Swing at \(swing.timestamp), peak \(swing.peakG ?? 0) g (on stop)")
            onSwing?(swing)
        }
    }
}
