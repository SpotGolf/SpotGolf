import CoreLocation
import CourseDataSwift
import Foundation
import Observation
import os

/// Detects ball contact during a round while the watch is within `zoneMargin` of any hole's
/// green, whichever hole is shown: there it subscribes to the accelerometer, device motion and
/// the microphone from `SensorInputs` and feeds them to a `ContactRunner`. It stops 10 s after
/// the watch leaves the zone, when the workout stops, and when the round ends. See
/// `plans/2026-10-06-putt-detection.md`.
@MainActor
@Observable
final class ContactMonitor {
    /// Meters from the green's edge the detector runs within: the zone the phone suggests putts
    /// in. The phone's Green Zone setting sets it for each round.
    var zoneMargin = HoleShape.chipZoneMargin

    /// Why a session on a green ended.
    enum StopReason: Equatable {
        case workoutStopped
        case leftGreen
        case roundEnded

        var text: String {
            switch self {
            case .workoutStopped: "the workout stopped"
            case .leftGreen: "left the green"
            case .roundEnded: "the round ended"
            }
        }

        var endReason: PuttCapture.EndReason {
            switch self {
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

    /// Called on the main actor as the detector goes on and off, for Developer Mode's segments. In
    /// order with the contacts: a stop comes after the contact the detector flushes on stopping.
    @ObservationIgnored var onSession: ((SessionChange) -> Void)?

    /// Called on the main actor with every candidate the stroke gate judged, while
    /// `recordsCandidates` said so when the session started.
    @ObservationIgnored var onDetectorCandidate: ((ContactDetector.Judged) -> Void)?

    /// Whether a session starting now records its candidates: while Developer Mode records the round.
    @ObservationIgnored var recordsCandidates: () -> Bool = { false }

    /// Called with each start and stop, for the round's stream.
    @ObservationIgnored var onEvent: ((StreamEvent) -> Void)?

    @ObservationIgnored private let sensors: SensorInputs
    @ObservationIgnored private let runner: ContactRunner
    @ObservationIgnored private var subscriptions: [SensorInputs.Subscription] = []
    /// The round the greens are for; another round gets new ones.
    @ObservationIgnored private var roundID: UUID?
    @ObservationIgnored private var greens = GreenTracker()
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
        if roundID != round.id {
            roundID = round.id
            greens = GreenTracker(courseSelection: round.courseSelection)
        }
        guard isWorkoutRunning() else {
            // Back on a green once the workout runs again
            greens.leave()
            if isRunning {
                stop(reason: .workoutStopped)
            }
            return
        }
        switch greens.update(location: location, zoneMargin: zoneMargin) {
        case .entered(let holeIndex):
            if !isRunning {
                start(hole: round.holeNumber(at: holeIndex))
            }
        case .left:
            if isRunning {
                stop(reason: .leftGreen)
            }
        case nil:
            break
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
        roundID = nil
        greens = GreenTracker()
        if isRunning {
            stop(reason: .roundEnded)
        }
    }

    /// Starts at the green of the hole numbered `hole`: its number, which differs from its
    /// index + 1 after a shotgun start.
    private func start(hole: Int) {
        isRunning = true
        startedAt = Date()
        runner.start(recordingCandidates: recordsCandidates())
        let runner = runner
        subscriptions = [
            sensors.subscribeAccelerometer { runner.addAccelerometer($0) },
            sensors.subscribeDeviceMotion { runner.addMotion($0) },
            sensors.subscribeMicrophone { buffer in
                runner.addAudio(buffer.samples, hostSeconds: buffer.hostTime, sampleRate: buffer.sampleRate)
            }
        ]
        Log.contacts.notice("Contact detection on at hole \(hole)")
        onEvent?(StreamEvent(code: .contactsOn, value: Float(hole)))
        // After a stop still flushing, so Developer Mode closes the last segment before it opens the next
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
        // Developer Mode hears of the stop after the contact the detector flushes, so the contact reaches the segment
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
