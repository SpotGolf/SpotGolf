import CoreLocation
import CourseDataSwift
import Foundation
import Observation
import os

/// Detects ball contact during a round while the watch is within `zoneMargin` of the display
/// hole's green: there it subscribes to the accelerometer, device motion and the microphone
/// from `SensorInputs` and feeds them to a `ContactRunner`. It stops 10 s after the watch
/// leaves the zone, when the display hole changes, when the workout stops, and when the round
/// ends. See `plans/2026-10-06-putt-detection.md`.
@MainActor
@Observable
final class ContactMonitor {
    /// The zone the phone suggests putts in.
    static let zoneMargin = HoleShape.chipZoneMargin
    /// Fixes beyond the zone for this long stop the detector.
    static let exitDelay: TimeInterval = 10

    private(set) var isRunning = false

    /// Called on the main actor with each contact.
    @ObservationIgnored var onContact: ((ContactEvent) -> Void)?

    /// Called with each start and stop, for the round's stream.
    @ObservationIgnored var onEvent: ((StreamEvent) -> Void)?

    @ObservationIgnored private let sensors: SensorInputs
    @ObservationIgnored private let runner: ContactRunner
    @ObservationIgnored private var subscriptions: [SensorInputs.Subscription] = []
    @ObservationIgnored private var holeIndex: Int?
    @ObservationIgnored private var green = HoleShape()
    @ObservationIgnored private var outsideSince: Date?
    @ObservationIgnored private var startedAt: Date?
    /// The accelerometer only runs with the workout, and nothing is scored without it.
    @ObservationIgnored private let isWorkoutRunning: () -> Bool

    init(sensors: SensorInputs, isWorkoutRunning: @escaping () -> Bool = { true }) {
        self.sensors = sensors
        self.isWorkoutRunning = isWorkoutRunning
        runner = ContactRunner(taps: sensors.taps)
        runner.onContact = { [weak self] contact in
            let event = ContactRunner.event(contact)
            Log.contacts.notice("Contact at \(event.timestamp): score \(event.score), burst \(event.burst) g, click \(event.click), turning \(event.turning) rad/s")
            Task { @MainActor in self?.onContact?(event) }
        }
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
            if !isRunning {
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
        isRunning = true
        startedAt = Date()
        runner.start()
        let runner = runner
        subscriptions = [
            sensors.subscribeAccelerometer { runner.addAccelerometer($0) },
            sensors.subscribeDeviceMotion { runner.addMotion($0) },
            sensors.subscribeMicrophone { buffer, hostSeconds in
                runner.addAudio(MicrophoneInput.samples(buffer), hostSeconds: hostSeconds, sampleRate: buffer.format.sampleRate)
            }
        ]
        let hole = holeIndex.map { $0 + 1 } ?? 0
        Log.contacts.notice("Contact detection on at hole \(hole)")
        onEvent?(StreamEvent(code: .contactsOn, value: Float(hole)))
    }

    private func stop(reason: String) {
        isRunning = false
        for subscription in subscriptions {
            subscription.cancel()
        }
        subscriptions = []
        runner.stop()
        let seconds = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        startedAt = nil
        Log.contacts.notice("Contact detection off after \(Int(seconds)) s: \(reason)")
        onEvent?(StreamEvent(code: .contactsOff, value: Float(seconds)))
    }
}
