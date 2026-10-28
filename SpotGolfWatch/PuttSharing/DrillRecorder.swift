import CoreLocation
import Foundation
import Observation
import SensorSources
import WatchKit

/// Runs a Putt Data Sharing session on the watch: its own workout and `ContactRunner`, every
/// stream written to one `CaptureWriter` segment, the drills' flow in `DrillSession`, and one
/// starting location. When the session ends it is packed and sent to the phone, and kept in the
/// outbox until the phone has it. See `plans/2026-10-27-putt-data-sharing.md`.
@MainActor
@Observable
final class DrillRecorder {
    enum State: Equatable {
        case idle
        /// Waiting for the workout to run.
        case starting
        case recording
        /// Packing the session for the phone, after it ended.
        case packing
    }

    private(set) var state = State.idle
    /// The drills' flow while recording.
    private(set) var session = DrillSession()
    /// What went wrong, for the screen.
    private(set) var problems: [String] = []
    /// The last session ended and is on its way to the phone.
    private(set) var lastSent: Date?
    /// Bytes waiting in the outbox for the phone.
    private(set) var outboxBytes: Int64 = 0
    /// Adds 1 each time the phone's settings arrive, so the page sees consent change.
    private(set) var settingsRevision = 0

    /// No session starts with more than this waiting for the phone.
    static let maxOutbox: Int64 = 500_000_000
    /// No session starts with less than this free.
    static let minFreeSpace: Int64 = 1_000_000_000

    /// Record sound. Off in tests: the simulator has no mic.
    @ObservationIgnored var microphone = true
    /// Bytes free on the watch, or nil when it does not say. Tests set it.
    @ObservationIgnored var freeSpace: () -> Int64? = { DrillRecorder.freeSpace() }
    /// The phone's consent and equipment profile. Tests set it.
    @ObservationIgnored var settings: () -> PhoneSettingsMessage? = { WatchSync.phoneSettings }
    /// Location updates for the starting fix.
    @ObservationIgnored var startLocation: () -> Void = {}
    @ObservationIgnored var stopLocation: () -> Void = {}
    @ObservationIgnored var locationDenied: () -> Bool = { false }

    @ObservationIgnored let root: URL
    @ObservationIgnored private let sensors: SensorInputs
    @ObservationIgnored private let workouts: WorkoutManager
    @ObservationIgnored private let sync: SyncService
    @ObservationIgnored private let isRoundActive: () -> Bool
    @ObservationIgnored private let runner: ContactRunner
    @ObservationIgnored private var writer: CaptureWriter?
    @ObservationIgnored private var subscriptions: [SensorInputs.Subscription] = []
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var startingFix: StartingFix?
    @ObservationIgnored private var fixTimeout: Task<Void, Never>?

    init(sensors: SensorInputs, workouts: WorkoutManager, sync: SyncService,
         root: URL = DrillRecorder.directory, isRoundActive: @escaping () -> Bool) {
        self.sensors = sensors
        self.workouts = workouts
        self.sync = sync
        self.root = root
        self.isRoundActive = isRoundActive
        runner = ContactRunner(taps: sensors.taps)
        // The main queue keeps contacts and candidates ahead of the segment's close, which follows them
        runner.onContact = { [weak self] contact in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.writer?.add(contact: contact) }
            }
        }
        runner.onCandidate = { [weak self] candidate in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.writer?.add(candidate: candidate) }
            }
        }
        // Batched sensor data only arrives once the workout runs, which is some time after `start`
        workouts.addRunningListener { [weak self] isRunning in
            if isRunning { self?.begin() }
        }
        updateOutbox()
    }

    /// The folder sessions are recorded and kept in.
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("putt-sharing", isDirectory: true)
    }

    private var sessionsFolder: URL { root.appendingPathComponent("sessions", isDirectory: true) }
    private var outbox: URL { root.appendingPathComponent("outbox", isDirectory: true) }

    /// The phone's player agreed to the current consent and the watch has what a session needs.
    var hasConsent: Bool {
        _ = settingsRevision
        guard let settings = settings(), let version = settings.consentVersion else { return false }
        return version >= PuttSharing.consentVersion && settings.sharerID != nil && settings.equipment != nil
    }

    /// The phone's settings arrived.
    func settingsChanged() {
        settingsRevision += 1
    }

    /// The outbox is too full to start another session.
    var isOutboxFull: Bool { outboxBytes >= Self.maxOutbox }

    // MARK: - Start

    func start() async {
        guard state == .idle, !isRoundActive(), hasConsent else { return }
        guard !isOutboxFull else {
            problems = [String(localized: "Waiting to send earlier sessions to your iPhone")]
            return
        }
        if let free = freeSpace(), free < Self.minFreeSpace {
            problems = [String(localized: "Not enough free space")]
            return
        }
        if microphone, MicrophonePermission.state == .notAsked {
            await MicrophonePermission.request()
        }
        problems = []
        state = .starting
        Log.puttSharing.notice("Drill session starting; waiting for the workout")
        workouts.start()
        if workouts.isRunning {
            begin()
        }
    }

    private func begin() {
        guard state == .starting else { return }
        let id = UUID()
        let folder = sessionsFolder.appendingPathComponent(id.uuidString, isDirectory: true)
        var meta = PuttCapture.Meta(startDate: Date(), startUptime: Uptime.now)
        meta.startBattery = Self.batteryLevel
        meta.microphone = microphone
        meta.captureID = id
        meta.hole = 0
        meta.segment = 1
        let device = WKInterfaceDevice.current()
        meta.wristLocation = device.wristLocation == .left ? "left" : "right"
        meta.crownOrientation = device.crownOrientation == .left ? "left" : "right"
        let writer: CaptureWriter
        do {
            writer = try CaptureWriter(directory: folder, meta: meta, savesData: true, microphone: microphone)
        } catch {
            Log.puttSharing.error("Could not create the session's files: \(String(describing: error))")
            problems = [String(localized: "Could not create files")]
            state = .idle
            endWorkout()
            return
        }
        self.writer = writer
        sessionID = id
        session = DrillSession()
        state = .recording
        saveDrills()
        Log.puttSharing.notice("Drill session \(id) recording; microphone \(self.microphone)")

        let runner = self.runner
        runner.start(recordingCandidates: true)
        subscriptions = [
            sensors.subscribeAccelerometer { batch in
                runner.addAccelerometer(batch)
                writer.add(accelerometer: batch)
            },
            sensors.subscribeDeviceMotion { batch in
                runner.addMotion(batch)
                writer.add(motion: batch)
            }
        ]
        if microphone {
            subscriptions.append(sensors.subscribeMicrophone { buffer in
                runner.addAudio(buffer.samples, hostSeconds: buffer.hostTime, sampleRate: buffer.sampleRate)
                writer.add(audio: buffer)
            })
        }
        startFix(at: writer.startDate)
    }

    /// Cancels a start still waiting for the workout.
    func cancelStart() {
        guard state == .starting else { return }
        sensors.tapped()
        Log.puttSharing.notice("Drill session cancelled before recording")
        state = .idle
        endWorkout()
    }

    // MARK: - Taps

    /// Seconds since the session started.
    private var now: Double { Uptime.now - (writer?.startUptime ?? Uptime.now) }

    func ready() {
        guard state == .recording, case .paused(let next) = session.step else { return }
        sensors.tapped()
        writer?.add(event: "ready", value: Double(next + 1))
        session.ready(at: now)
        saveDrills()
    }

    func done() {
        guard state == .recording, case .task(let drill, let task) = session.step else { return }
        sensors.tapped()
        writer?.add(event: "done", value: Double((drill + 1) * 10 + task + 1))
        session.done(at: now)
        saveDrills()
        if session.step == .finished { finish(reason: .stopped) }
    }

    func skipDrill() {
        guard state == .recording, let number = session.drillNumber else { return }
        sensors.tapped()
        writer?.add(event: "skipDrill", value: Double(number))
        session.skipDrill()
        saveDrills()
        if session.step == .finished { finish(reason: .stopped) }
    }

    /// Stop on the second page, or a round starting: the session ends and is sent.
    func stop() {
        switch state {
        case .starting:
            cancelStart()
        case .recording:
            sensors.tapped()
            writer?.add(event: "stop", value: 0)
            session.stop()
            saveDrills()
            finish(reason: .stopped)
        case .idle, .packing:
            return
        }
    }

    private func saveDrills() {
        guard let folder = writer?.directory else { return }
        write(session.record, to: folder.appendingPathComponent(DrillSession.Record.file))
    }

    // MARK: - Starting location

    private func startFix(at startDate: Date) {
        guard !locationDenied() else {
            startingFix = nil
            return
        }
        startingFix = StartingFix(startDate: startDate)
        startLocation()
        fixTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(StartingFix.maxWait))
            guard !Task.isCancelled else { return }
            self?.startingFix?.timeUp()
            self?.stopFix()
        }
    }

    /// GPS fixes while the starting location is wanted.
    func record(_ locations: [CLLocation]) {
        guard startingFix?.isDone == false else { return }
        if startingFix?.add(locations) == true {
            stopFix()
        }
    }

    private func stopFix() {
        fixTimeout?.cancel()
        fixTimeout = nil
        stopLocation()
    }

    // MARK: - Finish

    private func finish(reason: PuttCapture.EndReason) {
        guard state == .recording, let writer, let sessionID else { return }
        for subscription in subscriptions {
            subscription.cancel()
        }
        subscriptions = []
        startingFix?.timeUp()
        stopFix()
        let info = makeInfo(sessionID: sessionID, startDate: writer.startDate)
        let drills = session.drillsFinished
        let battery = Self.batteryLevel
        state = .packing
        endWorkout()
        // The stroke still open in the detector, and its candidates, reach the files first
        runner.stop { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.writer = nil
                    writer.finish(reason: reason, battery: battery) { [weak self] _ in
                        self?.pack(writer.directory, info: info, drillsFinished: drills, date: writer.startDate)
                    }
                }
            }
        }
        self.sessionID = nil
        Log.puttSharing.notice("Drill session \(sessionID) ended with \(drills) drills finished")
    }

    private func makeInfo(sessionID: UUID, startDate: Date) -> PuttSharing.Info {
        let settings = settings()
        let device = WKInterfaceDevice.current()
        var info = PuttSharing.Info(sessionID: sessionID, appVersion: AppVersion.text(),
                                    watchModel: Self.modelIdentifier, watchOSVersion: device.systemVersion,
                                    consentVersion: settings?.consentVersion ?? 0,
                                    sharerID: settings?.sharerID ?? UUID(),
                                    equipment: settings?.equipment ?? PuttSharing.Equipment())
        if let location = startingFix?.location(sessionStart: startDate) {
            info.location = location
        } else {
            info.locationStatus = startingFix == nil ? .denied : .noFix
        }
        startingFix = nil
        return info
    }

    /// Packs the finished session off the main actor, then sends it.
    private func pack(_ folder: URL, info: PuttSharing.Info, drillsFinished: Int, date: Date) {
        let outbox = self.outbox
        Task.detached(priority: .utility) {
            let result = Self.packSession(folder, info: info, outbox: outbox)
            await MainActor.run {
                self.packed(result, info: info, drillsFinished: drillsFinished, date: date)
            }
        }
    }

    /// Writes `sharing.json`, converts the audio and archives the folder into the outbox.
    /// Returns the archive, or nil when it could not be made; the folder is then kept.
    nonisolated static func packSession(_ folder: URL, info: PuttSharing.Info, outbox: URL) -> URL? {
        var info = info
        info.audioFile = SessionPacker.convertAudio(in: folder)
        let archive = outbox.appendingPathComponent("\(info.sessionID.uuidString).\(SessionPacker.archiveExtension)")
        do {
            try JSONEncoder.pretty.encode(info).write(to: folder.appendingPathComponent(PuttSharing.Info.file))
            try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
            try SessionPacker.archive(folder, to: archive, audioFile: info.audioFile)
            try FileManager.default.removeItem(at: folder)
            return archive
        } catch {
            Log.puttSharing.error("Could not pack session \(info.sessionID): \(String(describing: error))")
            return nil
        }
    }

    private func packed(_ archive: URL?, info: PuttSharing.Info, drillsFinished: Int, date: Date) {
        state = .idle
        guard let archive else {
            problems = [String(localized: "Could not pack the session")]
            return
        }
        let size = (try? archive.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let notice = PuttSessionNotice(sessionID: info.sessionID, date: date, drillsFinished: drillsFinished,
                                       size: size, hasLocation: info.location != nil)
        write(notice, to: archive.deletingPathExtension().appendingPathExtension("json"))
        send(archive, notice: notice)
        sync.queue(.puttSession(notice))
        lastSent = Date()
        updateOutbox()
    }

    // MARK: - Sending

    private func send(_ archive: URL, notice: PuttSessionNotice) {
        Log.puttSharing.notice("Sending session \(notice.sessionID), \(notice.size) bytes")
        sync.transport.transferFile(archive, metadata: [
            PuttSharing.FileKey.sessionID: notice.sessionID.uuidString,
            PuttSharing.FileKey.date: notice.date.timeIntervalSince1970,
            PuttSharing.FileKey.drillsFinished: notice.drillsFinished,
            PuttSharing.FileKey.hasLocation: notice.hasLocation
        ])
    }

    /// The phone has a session, or its transfer failed for good, which the next launch retries.
    func transferFinished(_ metadata: [String: Any], error: Error?) {
        guard let id = metadata[PuttSharing.FileKey.sessionID] as? String else { return }
        if let error {
            Log.puttSharing.error("Sending session \(id) failed: \(String(describing: error))")
            return
        }
        Log.puttSharing.notice("Session \(id) reached the phone")
        try? FileManager.default.removeItem(at: outbox.appendingPathComponent("\(id).\(SessionPacker.archiveExtension)"))
        try? FileManager.default.removeItem(at: outbox.appendingPathComponent("\(id).json"))
        updateOutbox()
    }

    /// At launch: finishes sessions a kill left unpacked, and sends again what is in the outbox
    /// and not on its way.
    func recoverAtLaunch() {
        CaptureWriter.finishUnfinished(under: sessionsFolder)
        let manager = FileManager.default
        let folders = (try? manager.contentsOfDirectory(at: sessionsFolder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for folder in folders where folder.isDirectory {
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            let record = (try? Data(contentsOf: folder.appendingPathComponent(DrillSession.Record.file)))
                .flatMap { try? JSONDecoder().decode(DrillSession.Record.self, from: $0) }
            let finished = record?.drillsFinished ?? 0
            let startDate = (try? Data(contentsOf: folder.appendingPathComponent(PuttCapture.metaFile)))
                .flatMap { try? PuttCapture.Meta(json: $0) }?.startDate ?? Date()
            Log.puttSharing.notice("Packing session \(id), left unpacked by a kill")
            startingFix = nil
            var info = makeInfo(sessionID: id, startDate: startDate)
            info.locationStatus = .noFix
            pack(folder, info: info, drillsFinished: finished, date: startDate)
        }
        let sending = Set(sync.transport.outstandingFileTransfers.compactMap { $0[PuttSharing.FileKey.sessionID] as? String })
        let waiting = (try? manager.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil)) ?? []
        for archive in waiting where archive.pathExtension == SessionPacker.archiveExtension {
            let id = archive.deletingPathExtension().lastPathComponent
            guard !sending.contains(id),
                  let data = try? Data(contentsOf: archive.deletingPathExtension().appendingPathExtension("json")),
                  let notice = try? JSONDecoder().decode(PuttSessionNotice.self, from: data) else { continue }
            send(archive, notice: notice)
        }
        updateOutbox()
    }

    private func updateOutbox() {
        let files = (try? FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        outboxBytes = files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    // MARK: - Pieces

    private func endWorkout() {
        if !isRoundActive() {
            workouts.stop()
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            try JSONEncoder.pretty.encode(value).write(to: url)
        } catch {
            Log.puttSharing.error("Could not write \(url.lastPathComponent): \(String(describing: error))")
        }
    }

    private static var batteryLevel: Double? {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        return level >= 0 ? Double(level) : nil
    }

    /// The hardware model, such as "Watch7,1".
    private static var modelIdentifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    private static func freeSpace() -> Int64? {
        let values = try? directory.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacity.map(Int64.init)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
