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
    /// Meters from the green's edge the detector runs within: the zone the phone suggests putts
    /// in. The phone's Green Zone setting sets it for each round.
    var zoneMargin = HoleShape.chipZoneMargin
    /// Fixes beyond the zone for this long stop the detector.
    static let exitDelay: TimeInterval = 10

    /// Why a session on a green ended.
    enum StopReason: Equatable {
        case holeAdvanced
        case workoutStopped
        case leftGreen
        case roundEnded

        var text: String {
            switch self {
            case .holeAdvanced: "the display hole changed"
            case .workoutStopped: "the workout stopped"
            case .leftGreen: "left the green"
            case .roundEnded: "the round ended"
            }
        }

        var endReason: PuttCapture.EndReason {
            switch self {
            case .holeAdvanced: .holeAdvanced
            case .workoutStopped: .workoutStopped
            case .leftGreen: .leftGreen
            case .roundEnded: .roundEnded
            }
        }
    }

    /// The detector going on at a green, with the hole 1-based, or off.
    enum SessionChange: Equatable {
        case started(hole: Int)
        case stopped(reason: StopReason)
    }

    private(set) var isRunning = false

    /// Called on the main actor with each contact.
    @ObservationIgnored var onContact: ((ContactEvent) -> Void)?

    /// Called on the main actor with each contact as the detector reported it, at its uptime.
    @ObservationIgnored var onDetectorContact: ((ContactDetector.Contact) -> Void)?

    /// Called on the main actor as the detector goes on and off, for Putt Lab's segments. In
    /// order with the contacts: a stop comes after the contact the detector flushes on stopping.
    @ObservationIgnored var onSession: ((SessionChange) -> Void)?

    /// Called on the main actor with every candidate the stroke gate judged, while
    /// `recordsCandidates` said so when the session started.
    @ObservationIgnored var onDetectorCandidate: ((ContactDetector.Judged) -> Void)?

    /// Whether a session starting now records its candidates: while Putt Lab records the round.
    @ObservationIgnored var recordsCandidates: () -> Bool = { false }

    /// Called with each start and stop, for the round's stream.
    @ObservationIgnored var onEvent: ((StreamEvent) -> Void)?

    @ObservationIgnored private let sensors: SensorInputs
    @ObservationIgnored private let runner: ContactRunner
    @ObservationIgnored private var subscriptions: [SensorInputs.Subscription] = []
    @ObservationIgnored private var holeIndex: Int?
    /// The display hole's number, which differs from its index + 1 after a shotgun start.
    @ObservationIgnored private var holeNumber = 0
    @ObservationIgnored private var green = HoleShape()
    @ObservationIgnored private var outsideSince: Date?
    @ObservationIgnored private var startedAt: Date?
    /// The accelerometer only runs with the workout, and nothing is scored without it.
    @ObservationIgnored private let isWorkoutRunning: () -> Bool

    init(sensors: SensorInputs, isWorkoutRunning: @escaping () -> Bool = { true }) {
        self.sensors = sensors
        self.isWorkoutRunning = isWorkoutRunning
        runner = ContactRunner(taps: sensors.taps)
        // The main queue keeps contacts, candidates and session changes in the order the runner sent them
        runner.onContact = { [weak self] contact in
            let event = ContactRunner.event(contact)
            Log.contacts.notice("Contact at \(event.timestamp): score \(event.score), burst \(event.burst) g, click \(event.click), turning \(event.turning) rad/s")
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.onContact?(event)
                    self?.onDetectorContact?(contact)
                }
            }
        }
        runner.onCandidate = { [weak self] candidate in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onDetectorCandidate?(candidate) }
            }
        }
    }

    /// Every GPS fix of the active round.
    func update(location: CLLocation, round: Round) {
        if holeIndex != round.displayHoleIndex {
            holeIndex = round.displayHoleIndex
            holeNumber = round.displayHoleNumber
            green = HoleShape(hole: round.displayCourseHole, course: round.course)
            outsideSince = nil
            if isRunning {
                stop(reason: .holeAdvanced)
            }
        }
        let point = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        guard let toGreen = green.metersToGreen(point) else { return }
        guard isWorkoutRunning() else {
            if isRunning {
                stop(reason: .workoutStopped)
            }
            return
        }
        if toGreen <= zoneMargin {
            outsideSince = nil
            if !isRunning {
                start()
            }
        } else if isRunning {
            if let outsideSince {
                if location.timestamp.timeIntervalSince(outsideSince) >= Self.exitDelay {
                    stop(reason: .leftGreen)
                }
            } else {
                outsideSince = location.timestamp
            }
        }
    }

    /// Runs `block` on the main actor after every contact, candidate and session change the
    /// detector has sent so far.
    func afterPending(_ block: @escaping @MainActor @Sendable () -> Void) {
        runner.afterQueued {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { block() }
            }
        }
    }

    func roundEnded() {
        holeIndex = nil
        if isRunning {
            stop(reason: .roundEnded)
        }
    }

    private func start() {
        isRunning = true
        startedAt = Date()
        runner.start(recordingCandidates: recordsCandidates())
        let runner = runner
        subscriptions = [
            sensors.subscribeAccelerometer { runner.addAccelerometer($0) },
            sensors.subscribeDeviceMotion { runner.addMotion($0) },
            sensors.subscribeMicrophone { buffer, hostSeconds in
                runner.addAudio(MicrophoneInput.samples(buffer), hostSeconds: hostSeconds, sampleRate: buffer.format.sampleRate)
            }
        ]
        let hole = holeIndex == nil ? 0 : holeNumber
        Log.contacts.notice("Contact detection on at hole \(hole)")
        onEvent?(StreamEvent(code: .contactsOn, value: Float(hole)))
        // After a stop still flushing, so Putt Lab closes the last segment before it opens the next
        runner.afterQueued { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onSession?(.started(hole: hole)) }
            }
        }
    }

    private func stop(reason: StopReason) {
        isRunning = false
        for subscription in subscriptions {
            subscription.cancel()
        }
        subscriptions = []
        // Putt Lab hears of the stop after the contact the detector flushes, so the contact reaches the segment
        runner.stop { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onSession?(.stopped(reason: reason)) }
            }
        }
        let seconds = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        startedAt = nil
        Log.contacts.notice("Contact detection off after \(Int(seconds)) s: \(reason.text)")
        onEvent?(StreamEvent(code: .contactsOff, value: Float(seconds)))
    }
}
