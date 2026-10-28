import CoreLocation
import SensorSources
import Foundation
import Observation
import os
import WatchKit

/// Records a round's putt capture in Developer Mode: raw accelerometer, device motion and
/// microphone data from `SensorInputs`, with the player's marks and the contacts found live.
/// The round starts the capture, and a `CaptureWriter` segment is written for each of
/// `ContactMonitor`'s sessions on a green, with the contacts the monitor finds. Captures are
/// kept for the last `keptRounds` rounds and deleted with their round. See
/// `plans/2026-10-12-putt-lab-in-rounds.md` and `plans/2026-10-27-developer-mode.md`.
@MainActor
@Observable
final class PuttCaptureRecorder {
    enum State: Equatable {
        case idle
        /// Between greens, with no segment open.
        case waiting
        case recording
    }

    private(set) var state = State.idle
    /// What went wrong with the files, for the screen. The sensors report their own problems.
    private(set) var problems: [String] = []
    /// Record sound. Off in tests: the simulator has no mic.
    var microphone = true
    /// Contacts found in the open segment so far, shown live.
    private(set) var contactCount = 0
    /// The hole of the open or last segment, 1-based.
    private(set) var hole = 0
    /// Segments written in the capture so far.
    private(set) var segmentCount = 0
    /// The user stopped the capture during the active round, so the round records no more.
    private(set) var stoppedInRound = false

    /// Captures are kept for this many rounds, the one starting among them.
    static let keptRounds = 5
    /// A segment does not start with less than this free on the watch.
    static let minFreeSpace: Int64 = 2_000_000_000
    /// Bytes free on the watch, or nil when it does not say. Tests set it.
    @ObservationIgnored var freeSpace: () -> Int64? = { PuttCaptureRecorder.freeSpace() }
    /// The folder captures are recorded into.
    @ObservationIgnored let root: URL
    /// The round's Green Zone in meters, written into each segment of a round.
    @ObservationIgnored var greenZone: () -> Double? = { nil }

    @ObservationIgnored private let sensors: SensorInputs
    @ObservationIgnored private var captureID: UUID?
    @ObservationIgnored private var roundID: UUID?
    @ObservationIgnored private var captureDirectory: URL?
    @ObservationIgnored private var writer: CaptureWriter?
    @ObservationIgnored private var subscriptions: [SensorInputs.Subscription] = []
    @ObservationIgnored private var inRound = false

    init(sensors: SensorInputs, root: URL = PuttCaptureRecorder.directory) {
        self.sensors = sensors
        self.root = root
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

    // MARK: - In a round

    /// The round started with Developer Mode on: a capture that records a segment per green.
    func startInRound(roundID: UUID) {
        stop()
        guard state == .idle else { return }
        inRound = true
        self.roundID = roundID
        stoppedInRound = false
        problems = []
        guard beginCapture() else { return }
        state = .waiting
        Log.developerMode.notice("Putt capture \(self.captureID?.uuidString ?? "") waiting for a green in round \(roundID)")
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

    /// A candidate the round's monitor judged, while a segment is open.
    func detectorCandidate(_ candidate: ContactDetector.Judged) {
        guard inRound else { return }
        writer?.add(candidate: candidate)
    }

    /// The round the capture is recording, or nil.
    var captureRoundID: UUID? { inRound ? roundID : nil }

    /// Developer Mode is recording the round, so the monitor's sessions should record their candidates.
    var recordsRound: Bool { inRound && state != .idle }

    // MARK: - Events and locations

    /// Something that just happened on the watch, into the open segment's events.
    func record(event: String, value: Double = 0) {
        writer?.add(event: event, value: value)
    }

    /// Something that happened on the watch at `date`, into the open segment's events.
    func record(event: String, value: Double, at date: Date) {
        writer?.add(event: event, value: value, at: date)
    }

    /// A stream event, at its own time, into the open segment's events.
    func record(_ event: StreamEvent) {
        writer?.add(event: event.name, value: Double(event.value), at: event.timestamp)
    }

    /// GPS fixes, into the open segment.
    func record(_ locations: [CLLocation]) {
        writer?.add(locations: locations)
    }

    /// The round ended: the capture ends with it.
    /// `roundID`, when given, must be the capture's round: a later round's capture is left alone.
    func roundEnded(roundID: UUID? = nil) {
        guard inRound, roundID == nil || roundID == self.roundID else { return }
        if state == .recording {
            closeSegment(reason: .roundEnded)
        }
        endCapture()
    }

    // MARK: - Keeping captures

    /// Deletes every capture but those of the `keptRounds - 1` most recent rounds other than
    /// `roundID`, which is starting, and every capture with no round. Called as a round starts,
    /// before its own capture is made.
    func pruneCaptures(keeping roundID: UUID) {
        var latest: [UUID: Date] = [:]
        let captures = Self.captures(in: root)
        for capture in captures {
            guard let round = capture.roundID, round != roundID else { continue }
            latest[round] = max(latest[round] ?? .distantPast, capture.date)
        }
        let kept = Set(latest.sorted { $0.value > $1.value }.prefix(Self.keptRounds - 1).map(\.key) + [roundID])
        for capture in captures where capture.roundID.map({ !kept.contains($0) }) ?? true {
            delete(capture.url)
        }
    }

    /// Deletes the round's captures. One still recording is closed first and deleted once its
    /// files are.
    func deleteCaptures(roundID: UUID) {
        let open = inRound && self.roundID == roundID ? captureDirectory : nil
        if let open {
            if state == .recording {
                closeSegment(reason: .roundEnded) { [weak self] in self?.delete(open) }
            } else {
                delete(open)
            }
            endCapture()
        }
        for capture in Self.captures(in: root) where capture.roundID == roundID && capture.url != open {
            delete(capture.url)
        }
    }

    private func delete(_ capture: URL) {
        do {
            try FileManager.default.removeItem(at: capture)
            Log.developerMode.notice("Deleted capture \(capture.lastPathComponent)")
        } catch {
            Log.developerMode.error("Could not delete capture \(capture.lastPathComponent): \(String(describing: error))")
        }
    }

    /// A capture folder, its round and its date: the first segment's, or the folder's creation
    /// when no segment has details yet.
    struct Capture: Equatable {
        let url: URL
        let roundID: UUID?
        let date: Date
    }

    /// The capture folders under `root`.
    static func captures(in root: URL) -> [Capture] {
        let manager = FileManager.default
        let folders = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey])) ?? []
        return folders.filter(\.isDirectory).map { folder in
            var date = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            var roundID: UUID?
            let segments = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            if let first = segments.filter(\.isDirectory).min(by: { $0.lastPathComponent < $1.lastPathComponent }),
               let data = try? Data(contentsOf: first.appendingPathComponent(PuttCapture.metaFile)),
               let meta = try? PuttCapture.Meta(json: data) {
                date = meta.startDate
                roundID = meta.roundID
            }
            return Capture(url: folder, roundID: roundID, date: date)
        }
    }

    // MARK: - Capture

    /// Makes the capture's folder. False, with a problem shown, when it can't be made.
    private func beginCapture() -> Bool {
        let id = UUID()
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            Log.developerMode.error("Could not create the capture folder: \(String(describing: error))")
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

    private func endCapture() {
        captureID = nil
        captureDirectory = nil
        roundID = nil
        inRound = false
        state = .idle
    }

    // MARK: - Segments

    private func openSegment(hole: Int) {
        guard let captureID, let captureDirectory else { return }
        if let free = freeSpace(), free < Self.minFreeSpace {
            Log.developerMode.error("No segment: \(free / 1_000_000) MB free on the watch")
            problems = [String(localized: "Not enough free space")]
            return
        }
        let startDate = Date()
        let startUptime = Uptime.now
        var meta = PuttCapture.Meta(startDate: startDate, startUptime: startUptime)
        meta.startBattery = Self.batteryLevel
        meta.microphone = microphone
        meta.captureID = captureID
        meta.roundID = roundID
        meta.hole = hole
        meta.segment = segmentCount + 1
        meta.greenZone = greenZone()
        let device = WKInterfaceDevice.current()
        meta.wristLocation = device.wristLocation == .left ? "left" : "right"
        meta.crownOrientation = device.crownOrientation == .left ? "left" : "right"
        let directory = captureDirectory.appendingPathComponent(PuttCapture.segmentFolder(segmentCount + 1, hole: hole), isDirectory: true)
        let writer: CaptureWriter
        do {
            writer = try CaptureWriter(directory: directory, meta: meta, savesData: true, microphone: microphone)
        } catch {
            Log.developerMode.error("Could not create the segment's files: \(String(describing: error))")
            problems = [String(localized: "Could not create files")]
            return
        }
        self.writer = writer
        segmentCount += 1
        self.hole = hole
        contactCount = 0
        problems = []
        state = .recording
        Log.developerMode.notice("Segment \(self.segmentCount) of capture \(captureID) recording at hole \(hole); microphone \(self.microphone)")

        subscriptions = [
            sensors.subscribeAccelerometer { batch in writer.add(accelerometer: batch) },
            sensors.subscribeDeviceMotion { batch in writer.add(motion: batch) }
        ]
        if microphone {
            subscriptions.append(sensors.subscribeMicrophone { buffer in writer.add(audio: buffer) })
        }
    }

    /// Closes the open segment. `then` runs once its files are closed.
    private func closeSegment(reason: PuttCapture.EndReason, then: @escaping @MainActor () -> Void = {}) {
        guard let writer else { return }
        for subscription in subscriptions {
            subscription.cancel()
        }
        subscriptions = []
        // The monitor reports a stop after the contact it flushes, so nothing is left to come
        self.writer = nil
        writer.finish(reason: reason, battery: Self.batteryLevel) { _ in then() }
    }

    private func found(_ contact: ContactDetector.Contact) {
        guard let writer else { return }
        writer.add(contact: contact)
        contactCount += 1
        // No haptic: it would only add contacts the phone could suggest
        Log.developerMode.notice("Contact at \(contact.time - writer.startUptime) s: score \(contact.score)")
    }

    // MARK: - Marks

    /// Records that a stroke with this label just happened. The tap itself is not a stroke.
    func mark(_ label: PuttCapture.MarkLabel) {
        guard state == .recording, let writer else { return }
        let mark = writer.mark(label)
        Log.developerMode.notice("Mark \(label.rawValue) at \(mark.t) s")
        sensors.play(.success)
    }

    /// Takes back the last mark, tapped by mistake.
    func undoLastMark() {
        guard state == .recording, let writer else { return }
        writer.undoLastMark()
        Log.developerMode.notice("Undid the last mark")
        sensors.play(.click)
    }

    // MARK: - Stop

    /// Stops the capture: the round records no more segments.
    func stop() {
        switch state {
        case .idle:
            return
        case .waiting:
            break
        case .recording:
            sensors.tapped()
            closeSegment(reason: .stopped)
        }
        Log.developerMode.notice("Putt capture stopped for the rest of the round")
        stoppedInRound = true
        endCapture()
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
