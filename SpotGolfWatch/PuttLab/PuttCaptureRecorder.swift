import CoreMotion
import Foundation
import Observation
import os
import WatchKit

/// Records a putt capture: raw accelerometer, device motion and microphone data from
/// `SensorInputs`, with the player's marks and the contacts found live, one `CaptureWriter`
/// per segment. Outside a round a capture is one segment from Start Capture to Stop, with a
/// workout of its own and its own `ContactRunner`. In a round the round starts the capture,
/// and a segment is written for each of `ContactMonitor`'s sessions on a green, with the
/// contacts the monitor finds, so one detector runs. See `plans/2026-10-12-putt-lab-in-rounds.md`.
@MainActor
@Observable
final class PuttCaptureRecorder {
    enum State: Equatable {
        case idle
        /// Outside a round: waiting for the workout to run.
        case starting
        /// In a round: between greens, with no segment open.
        case waiting
        case recording
    }

    private(set) var state = State.idle
    /// What went wrong with the files, for the screen. The sensors report their own problems.
    private(set) var problems: [String] = []
    private(set) var micPermission = MicrophoneInput.permission
    /// Record sound. Off to measure the sensors' battery cost alone.
    var microphone = true
    /// Write readings and audio. Off for a battery test: the sensors and the scoring math run,
    /// nothing is written, and the capture keeps only its counts and battery levels.
    var savesData = true
    /// Contacts found in the open segment so far, shown live.
    private(set) var contactCount = 0
    /// The hole of the open or last segment, 1-based; 0 outside a round.
    private(set) var hole = 0
    /// Segments written in the capture so far.
    private(set) var segmentCount = 0
    /// The user stopped the capture during the active round, so the round records no more.
    private(set) var stoppedInRound = false

    /// A segment does not start with less than this free on the watch.
    static let minFreeSpace: Int64 = 2_000_000_000
    /// Bytes free on the watch, or nil when it does not say. Tests set it.
    @ObservationIgnored var freeSpace: () -> Int64? = { PuttCaptureRecorder.freeSpace() }
    /// The folder captures are recorded into.
    @ObservationIgnored let root: URL

    @ObservationIgnored private let sensors: SensorInputs
    @ObservationIgnored private let workouts: WorkoutManager
    /// A round is recording: its workout must be left running, and it owns the capture.
    @ObservationIgnored private let isRoundActive: () -> Bool
    @ObservationIgnored private var captureID: UUID?
    @ObservationIgnored private var roundID: UUID?
    @ObservationIgnored private var captureDirectory: URL?
    @ObservationIgnored private var writer: CaptureWriter?
    @ObservationIgnored private var subscriptions: [SensorInputs.Subscription] = []
    // Outside a round, the same detector a round runs, so the page shows what a round would record
    @ObservationIgnored private let runner: ContactRunner
    @ObservationIgnored private var inRound = false

    init(sensors: SensorInputs, workouts: WorkoutManager, root: URL = PuttCaptureRecorder.directory,
         isRoundActive: @escaping () -> Bool) {
        self.sensors = sensors
        self.workouts = workouts
        self.root = root
        self.isRoundActive = isRoundActive
        runner = ContactRunner(taps: sensors.taps)
        runner.onContact = { [weak self] contact in
            Task { @MainActor in self?.found(contact) }
        }
        // Batched sensor data only arrives once the workout runs, which is some time after `start`
        workouts.addRunningListener { [weak self] isRunning in
            if isRunning { self?.beginStandalone() }
        }
    }

    /// The root folder captures are recorded into.
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(PuttCapture.directoryName, isDirectory: true)
    }

    /// Finishes segments left open by a kill. Called once at launch.
    func recoverUnfinished() {
        CaptureWriter.finishUnfinished(under: root)
    }

    // MARK: - Outside a round

    func start() async {
        guard state == .idle, !isRoundActive() else { return }
        if micPermission == .notAsked {
            await MicrophoneInput.requestPermission()
            micPermission = MicrophoneInput.permission
        }
        state = .starting
        problems = []
        Log.puttLab.notice("Putt capture starting; waiting for the workout")
        workouts.start()
        if workouts.isRunning {
            beginStandalone()
        }
    }

    private func beginStandalone() {
        guard state == .starting else { return }
        inRound = false
        roundID = nil
        guard beginCapture() else { return }
        openSegment(hole: 0)
        if state != .recording {
            endCapture(endWorkout: true)
        }
    }

    // MARK: - In a round

    /// The round started with Putt Lab on: a capture that records a segment per green.
    func startInRound(roundID: UUID) {
        stop()
        guard state == .idle else { return }
        inRound = true
        self.roundID = roundID
        stoppedInRound = false
        problems = []
        guard beginCapture() else { return }
        state = .waiting
        Log.puttLab.notice("Putt capture \(self.captureID?.uuidString ?? "") waiting for a green in round \(roundID)")
    }

    /// The contact monitor went on or off on a green.
    func sessionChanged(_ change: ContactMonitor.SessionChange) {
        guard inRound else { return }
        switch change {
        case .started(let hole):
            guard state == .waiting else { return }
            openSegment(hole: hole)
        case .stopped(let reason):
            guard state == .recording else { return }
            closeSegment(reason: reason.endReason)
            state = .waiting
        }
    }

    /// A contact the round's monitor found, while a segment is open.
    func detectorContact(_ contact: ContactDetector.Contact) {
        guard inRound else { return }
        found(contact)
    }

    /// The round ended: the capture ends with it.
    func roundEnded() {
        guard inRound else { return }
        if state == .recording {
            closeSegment(reason: .roundEnded)
        }
        endCapture(endWorkout: false)
    }

    // MARK: - Capture

    /// Makes the capture's folder. False, with a problem shown, when it can't be made.
    private func beginCapture() -> Bool {
        let id = UUID()
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            Log.puttLab.error("Could not create the capture folder: \(String(describing: error))")
            problems.append(String(localized: "Could not create files"))
            state = .idle
            inRound = false
            return false
        }
        captureID = id
        captureDirectory = directory
        segmentCount = 0
        return true
    }

    private func endCapture(endWorkout: Bool) {
        captureID = nil
        captureDirectory = nil
        roundID = nil
        inRound = false
        state = .idle
        if endWorkout {
            workouts.stop()
        }
    }

    // MARK: - Segments

    private func openSegment(hole: Int) {
        guard let captureID, let captureDirectory else { return }
        if let free = freeSpace(), free < Self.minFreeSpace {
            Log.puttLab.error("No segment: \(free / 1_000_000) MB free on the watch")
            problems = [String(localized: "Not enough free space")]
            return
        }
        let startDate = Date()
        let startUptime = Uptime.now
        var meta = PuttCapture.Meta(startDate: startDate, startUptime: startUptime)
        meta.startBattery = Self.batteryLevel
        meta.microphone = microphone
        meta.savesData = savesData
        meta.captureID = captureID
        meta.roundID = roundID
        meta.hole = hole
        meta.segment = segmentCount + 1
        let directory = captureDirectory.appendingPathComponent(PuttCapture.segmentFolder(segmentCount + 1, hole: hole), isDirectory: true)
        let writer: CaptureWriter
        do {
            writer = try CaptureWriter(directory: directory, meta: meta, savesData: savesData, microphone: microphone)
        } catch {
            Log.puttLab.error("Could not create the segment's files: \(String(describing: error))")
            problems = [String(localized: "Could not create files")]
            return
        }
        self.writer = writer
        segmentCount += 1
        self.hole = hole
        contactCount = 0
        problems = []
        state = .recording
        Log.puttLab.notice("Segment \(self.segmentCount) of capture \(captureID) recording at hole \(hole); microphone \(self.microphone), saving \(self.savesData)")

        let runner = inRound ? nil : self.runner
        runner?.start()
        subscriptions = [
            sensors.subscribeAccelerometer { batch in
                runner?.addAccelerometer(batch)
                writer.add(accelerometer: batch)
            },
            sensors.subscribeDeviceMotion { batch in
                runner?.addMotion(batch)
                writer.add(motion: batch)
            }
        ]
        if microphone {
            subscriptions.append(sensors.subscribeMicrophone { buffer, hostSeconds in
                runner?.addAudio(MicrophoneInput.samples(buffer), hostSeconds: hostSeconds, sampleRate: buffer.format.sampleRate)
                writer.add(audio: buffer, hostSeconds: hostSeconds)
            })
        }
    }

    private func closeSegment(reason: PuttCapture.EndReason) {
        guard let writer else { return }
        for subscription in subscriptions {
            subscription.cancel()
        }
        subscriptions = []
        self.writer = nil
        let battery = Self.batteryLevel
        if inRound {
            writer.finish(reason: reason, battery: battery) { _ in }
        } else {
            // The stroke still open in the detector is reported first, so it reaches contacts.csv
            runner.stop {
                writer.finish(reason: reason, battery: battery) { _ in }
            }
        }
    }

    private func found(_ contact: ContactDetector.Contact) {
        guard let writer else { return }
        writer.add(contact: contact)
        contactCount += 1
        Log.puttLab.notice("Contact at \(contact.time - writer.startUptime) s: score \(contact.score)")
        // In a round a haptic would only add contacts the phone could suggest
        if !inRound {
            sensors.play(.directionUp)
        }
    }

    // MARK: - Marks

    /// Records that a stroke with this label just happened. The tap itself is not a stroke.
    func mark(_ label: PuttCapture.MarkLabel) {
        guard state == .recording, let writer else { return }
        let mark = writer.mark(label)
        Log.puttLab.notice("Mark \(label.rawValue) at \(mark.t) s")
        sensors.play(.success)
    }

    /// Takes back the last mark, tapped by mistake.
    func undoLastMark() {
        guard state == .recording, let writer else { return }
        writer.undoLastMark()
        Log.puttLab.notice("Undid the last mark")
        sensors.play(.click)
    }

    // MARK: - Stop

    /// Stops the capture. Outside a round this also cancels a start still waiting; in a round
    /// the round records no more segments.
    func stop() {
        switch state {
        case .idle:
            return
        case .starting:
            sensors.tapped()
            Log.puttLab.notice("Putt capture cancelled before recording")
            endCapture(endWorkout: !isRoundActive())
        case .waiting:
            Log.puttLab.notice("Putt capture stopped for the rest of the round")
            stoppedInRound = true
            endCapture(endWorkout: false)
        case .recording:
            sensors.tapped()
            closeSegment(reason: .stopped)
            if inRound {
                Log.puttLab.notice("Putt capture stopped for the rest of the round")
                stoppedInRound = true
            }
            endCapture(endWorkout: !inRound && !isRoundActive())
        }
    }

    // MARK: - Device

    /// The battery level, to see what a capture costs. Nil when the watch does not say.
    private static var batteryLevel: Double? {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        return level >= 0 ? Double(level) : nil
    }

    /// Bytes free for the app's files, or nil when the system does not say.
    private static func freeSpace() -> Int64? {
        let values = try? directory.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacity.map(Int64.init)
    }
}
