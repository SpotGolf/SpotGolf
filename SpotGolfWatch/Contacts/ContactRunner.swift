import CoreMotion
import Foundation
import os

/// Runs a `ContactDetector` on its own queue, fed from the sensor and audio threads, and hands
/// each contact to `onContact` on that queue. Readings within `TapGuard.window` of a tap on the
/// app's own buttons are dropped: a tap is a loud 2 to 3.6 g knock on the watch.
final class ContactRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "golf.spot.SpotGolf.contacts", qos: .userInitiated)
    private var detector = ContactDetector()
    private let lock = NSLock()
    private var active = false
    private let taps: TapGuard

    /// Called on the runner's queue. Times are on the uptime clock.
    var onContact: ((ContactDetector.Contact) -> Void)?

    init(taps: TapGuard) {
        self.taps = taps
    }

    /// Input is taken only between `start` and `stop`.
    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    private func setActive(_ value: Bool) {
        lock.lock()
        active = value
        lock.unlock()
    }

    /// Starts a fresh detector. Input before this is dropped.
    func start() {
        setActive(true)
        queue.async {
            self.detector = ContactDetector()
        }
    }

    /// Drops input from now on, reports the stroke still being scored, then calls `completion`
    /// on the queue.
    func stop(completion: (@Sendable () -> Void)? = nil) {
        guard isActive else {
            completion?()
            return
        }
        setActive(false)
        queue.async {
            for contact in self.detector.flush() {
                self.onContact?(contact)
            }
            completion?()
        }
    }

    func addAudio(_ samples: [Float], hostSeconds: Double, sampleRate: Double) {
        guard isActive else { return }
        queue.async {
            self.detector.addAudio(samples, startTime: hostSeconds, sampleRate: sampleRate)
        }
    }

    func addMotion(_ batch: [CMDeviceMotion]) {
        guard isActive else { return }
        let rotations = batch.map { motion in
            let r = motion.rotationRate
            return ContactDetector.Rotation(time: motion.timestamp, rate: (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot())
        }
        queue.async {
            self.detector.addRotations(rotations)
        }
    }

    /// Accelerometer readings, then an evaluation: contacts of strokes that are over are reported.
    func addAccelerometer(_ batch: [CMAccelerometerData]) {
        guard isActive else { return }
        let readings = batch.compactMap { data -> ContactDetector.Reading? in
            guard !taps.covers(uptime: data.timestamp) else { return nil }
            let a = data.acceleration
            return ContactDetector.Reading(time: data.timestamp, x: a.x, y: a.y, z: a.z)
        }
        queue.async {
            self.detector.addReadings(readings)
            for contact in self.detector.evaluate() {
                self.onContact?(contact)
            }
        }
    }

    /// A contact as the stream records it.
    static func event(_ contact: ContactDetector.Contact) -> ContactEvent {
        let bootDate = Date(timeIntervalSinceNow: -ProcessInfo.processInfo.systemUptime)
        return ContactEvent(timestamp: bootDate.addingTimeInterval(contact.time), score: Float(contact.score),
                            burst: Float(contact.burst), click: Float(contact.click), turning: Float(contact.turning))
    }
}

/// The times of taps on the app's own buttons, which the detectors ignore. Kept on the uptime
/// clock the sensor readings use, so no clock conversion sits between a tap and its readings.
/// Written on the main actor, read on the sensor threads.
final class TapGuard: @unchecked Sendable {
    /// Readings this close to a tap, either side, are ignored.
    static let window: TimeInterval = 1

    private let lock = NSLock()
    private var taps: [Double] = []

    func tapped(atUptime uptime: Double = ProcessInfo.processInfo.systemUptime) {
        lock.lock()
        taps.append(uptime)
        taps.removeAll { uptime - $0 > 10 }
        lock.unlock()
    }

    /// Whether a reading at this uptime falls within `window` of a tap.
    func covers(uptime: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return taps.contains { abs(uptime - $0) <= Self.window }
    }
}
