import CoreLocation
import CoreMotion
import CourseDataSwift
import Foundation
import Observation
import os

/// Detects ball contact during a round while the watch is within `zoneMargin` of the display
/// hole's green: there it starts the mic and device motion, takes the accelerometer batches
/// `SwingDetector` already receives, and reports each contact. It stops 10 s after the watch
/// leaves the zone, when the display hole changes, and when the round ends. See
/// `plans/2026-10-06-putt-detection.md`.
@MainActor
@Observable
final class ContactMonitor {
    /// The zone the phone suggests putts in.
    static let zoneMargin = HoleShape.chipZoneMargin
    /// Fixes beyond the zone for this long stop the detector.
    static let exitDelay: TimeInterval = 10
    /// After the mic refuses to start, or its permission is missing, the next try waits this long.
    static let retryDelay: TimeInterval = 60

    private(set) var isRunning = false

    /// Called on the main actor with each contact.
    @ObservationIgnored var onContact: ((ContactEvent) -> Void)?

    let runner: ContactRunner
    let taps: TapGuard

    private let motionManager = CMBatchedSensorManager()
    private var microphone: MicrophoneInput?
    private var holeIndex: Int?
    private var green = HoleShape()
    private var outsideSince: Date?
    private var startedAt: Date?
    private var retryAfter: Date?
    /// The accelerometer only runs with the workout, and nothing is scored without it.
    private let isWorkoutRunning: () -> Bool

    init(taps: TapGuard = TapGuard(), isWorkoutRunning: @escaping () -> Bool = { true }) {
        self.taps = taps
        self.isWorkoutRunning = isWorkoutRunning
        runner = ContactRunner(taps: taps)
        runner.onContact = { [weak self] contact in
            let event = ContactRunner.event(contact)
            Log.contacts.notice("Contact at \(event.timestamp, privacy: .public): score \(event.score, privacy: .public), burst \(event.burst, privacy: .public) g, click \(event.click, privacy: .public), turning \(event.turning, privacy: .public) rad/s")
            Task { @MainActor in self?.onContact?(event) }
        }
    }

    /// A tap on one of the app's buttons: readings around it are ignored.
    func tapped() {
        taps.tapped()
    }

    /// Every GPS fix of the active round.
    func update(location: CLLocation, round: Round) {
        if holeIndex != round.displayHoleIndex {
            holeIndex = round.displayHoleIndex
            green = HoleShape(hole: round.displayCourseHole, course: round.course)
            outsideSince = nil
            if isRunning {
                stop(reason: "the display hole changed")
            }
        }
        let point = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        guard let toGreen = green.metersToGreen(point) else { return }
        guard isWorkoutRunning() else {
            if isRunning {
                stop(reason: "the workout stopped")
            }
            return
        }
        if toGreen <= Self.zoneMargin {
            outsideSince = nil
            if !isRunning, retryAfter.map({ Date() >= $0 }) ?? true {
                start()
            }
        } else if isRunning {
            if let outsideSince {
                if location.timestamp.timeIntervalSince(outsideSince) >= Self.exitDelay {
                    stop(reason: "left the green")
                }
            } else {
                outsideSince = location.timestamp
            }
        }
    }

    func roundEnded() {
        holeIndex = nil
        if isRunning {
            stop(reason: "the round ended")
        }
    }

    private func start() {
        retryAfter = nil
        guard MicrophoneInput.permission == .granted else {
            Log.contacts.error("Contact detection off: microphone permission \(String(describing: MicrophoneInput.permission), privacy: .public); trying again in \(Int(Self.retryDelay), privacy: .public) s")
            retryAfter = Date().addingTimeInterval(Self.retryDelay)
            return
        }
        let runner = runner
        let microphone = MicrophoneInput { samples, hostSeconds, sampleRate in
            runner.addAudio(samples, hostSeconds: hostSeconds, sampleRate: sampleRate)
        }
        do {
            try microphone.start(to: nil, captureStartUptime: 0)
        } catch {
            // Nothing can be scored without the click, so nothing else starts either
            Log.contacts.error("Could not start the microphone: \(String(describing: error), privacy: .public); trying again in \(Int(Self.retryDelay), privacy: .public) s")
            retryAfter = Date().addingTimeInterval(Self.retryDelay)
            return
        }
        self.microphone = microphone
        isRunning = true
        startedAt = Date()
        runner.start()
        if CMBatchedSensorManager.isDeviceMotionSupported {
            // CoreMotion calls this on its own queue, so @Sendable: a plain closure made here
            // would count as main-actor code, and Swift 6 traps when it runs anywhere else
            motionManager.startDeviceMotionUpdates { @Sendable batch, error in
                if let error {
                    Log.contacts.error("Device motion error: \(String(describing: error), privacy: .public)")
                }
                if let batch {
                    runner.addMotion(batch)
                }
            }
        } else {
            Log.contacts.error("Batched device motion not supported; contacts will not pass the turning gate")
        }
        Log.contacts.notice("Contact detection on at hole \(self.holeIndex.map { $0 + 1 } ?? 0, privacy: .public)")
    }

    private func stop(reason: String) {
        isRunning = false
        runner.stop()
        motionManager.stopDeviceMotionUpdates()
        microphone?.stop()
        microphone = nil
        let seconds = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        startedAt = nil
        Log.contacts.notice("Contact detection off after \(Int(seconds), privacy: .public) s: \(reason, privacy: .public)")
    }
}
