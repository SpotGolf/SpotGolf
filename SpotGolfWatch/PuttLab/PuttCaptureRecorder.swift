import CoreMotion
import Foundation
import Observation
import os
import WatchKit

/// Records a putt capture: raw accelerometer, device motion and microphone data from
/// `SensorInputs`, with the player's marks and the contacts the detector finds live, into one
/// folder per capture. Needs a workout for the batched sensors, so it starts one and ends it
/// when the capture stops, unless a round is using it.
@MainActor
@Observable
final class PuttCaptureRecorder {
    enum State: Equatable {
        case idle
        /// Waiting for the workout to run.
        case starting
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
    /// Contacts the detector found so far, shown live.
    private(set) var contactCount = 0

    let uploader: PuttCaptureUploader

    @ObservationIgnored private let sensors: SensorInputs
    @ObservationIgnored private let workouts: WorkoutManager
    /// A round is recording: its workout must be left running.
    @ObservationIgnored private let isRoundActive: () -> Bool
    @ObservationIgnored private var meta: PuttCapture.Meta?
    @ObservationIgnored private var directory: URL?
    // Every file write happens here, off the sensor and audio threads' own queues
    @ObservationIgnored private let io = DispatchQueue(label: "golf.spot.SpotGolf.puttCapture", qos: .utility)
    @ObservationIgnored private var accelHandle: FileHandle?
    @ObservationIgnored private var motionHandle: FileHandle?
    @ObservationIgnored private var marksHandle: FileHandle?
    @ObservationIgnored private var contactsHandle: FileHandle?
    @ObservationIgnored private var audioWriter: CaptureAudioWriter?
    // The capture's zero on the uptime clock, until its files are closed
    @ObservationIgnored private var captureStartUptime: Double?
    @ObservationIgnored private var subscriptions: [SensorInputs.Subscription] = []
    // The same detector a round runs, so the page shows what a round would record
    @ObservationIgnored private let runner: ContactRunner
    // Readings written so far, counted on the main actor
    @ObservationIgnored private var accelCount = 0
    @ObservationIgnored private var motionCount = 0

    init(sensors: SensorInputs, workouts: WorkoutManager, uploader: PuttCaptureUploader, isRoundActive: @escaping () -> Bool) {
        self.sensors = sensors
        self.workouts = workouts
        self.uploader = uploader
        self.isRoundActive = isRoundActive
        runner = ContactRunner(taps: sensors.taps)
        runner.onContact = { [weak self] contact in
            Task { @MainActor in self?.found(contact) }
        }
        // Batched sensor data only arrives once the workout runs, which is some time after `start`
        workouts.addRunningListener { [weak self] isRunning in
            if isRunning { self?.beginRecording() }
        }
    }

    private func found(_ contact: ContactDetector.Contact) {
        // Still written after Stop: the stroke open at the end is flushed before the files close
        guard let startUptime = captureStartUptime, contactsHandle != nil else { return }
        contactCount += 1
        let line = "\(contact.time - startUptime),\(contact.score),\(contact.burst),\(contact.click),\(contact.turning)\n"
        let handle = contactsHandle
        io.async { Self.write(Data(line.utf8), to: handle, name: "contacts") }
        Log.puttLab.notice("Contact at \(contact.time - startUptime) s: score \(contact.score)")
        WKInterfaceDevice.current().play(.directionUp)
    }

    /// The root folder captures are recorded into.
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("putt-captures", isDirectory: true)
    }

    // MARK: - Start

    func start() async {
        guard state == .idle else { return }
        if micPermission == .notAsked {
            await MicrophoneInput.requestPermission()
            micPermission = MicrophoneInput.permission
        }
        state = .starting
        problems = []
        Log.puttLab.notice("Putt capture starting; waiting for the workout")
        workouts.start()
        if workouts.isRunning {
            beginRecording()
        }
    }

    private func beginRecording() {
        guard state == .starting else { return }
        let startDate = Date()
        let startUptime = Uptime.now
        var meta = PuttCapture.Meta(startDate: startDate, startUptime: startUptime)
        meta.startBattery = Self.batteryLevel
        meta.microphone = microphone
        meta.savesData = savesData
        let directory = Self.directory.appendingPathComponent(meta.id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if savesData {
                accelHandle = try Self.createFile(directory.appendingPathComponent(PuttCapture.accelFile))
                motionHandle = try Self.createFile(directory.appendingPathComponent(PuttCapture.motionFile))
            }
            marksHandle = try Self.createFile(directory.appendingPathComponent(PuttCapture.marksFile),
                                              header: PuttCapture.Mark.csvHeader + "\n")
            contactsHandle = try Self.createFile(directory.appendingPathComponent(PuttCapture.contactsFile),
                                                 header: PuttCapture.contactsHeader + "\n")
            try meta.json().write(to: directory.appendingPathComponent(PuttCapture.metaFile))
        } catch {
            Log.puttLab.error("Could not create the capture files: \(String(describing: error))")
            problems.append(String(localized: "Could not create files"))
            cleanUp(endWorkout: !isRoundActive())
            return
        }
        self.meta = meta
        self.directory = directory
        captureStartUptime = startUptime
        state = .recording
        accelCount = 0
        motionCount = 0
        contactCount = 0
        runner.start()
        Log.puttLab.notice("Putt capture \(meta.id) recording; microphone \(self.microphone), saving \(self.savesData)")

        subscriptions = [subscribeAccelerometer(startUptime: startUptime), subscribeDeviceMotion(startUptime: startUptime)]
        if microphone {
            subscriptions.append(subscribeMicrophone(in: savesData ? directory : nil, startUptime: startUptime))
        }
    }

    /// The battery level, to see what a capture costs. Nil when the watch does not say.
    private static var batteryLevel: Double? {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        return level >= 0 ? Double(level) : nil
    }

    private static func createFile(_ url: URL, header: String = "") throws -> FileHandle {
        try Data(header.utf8).write(to: url)
        return try FileHandle(forWritingTo: url)
    }

    private func subscribeAccelerometer(startUptime: Double) -> SensorInputs.Subscription {
        let io = io, handle = accelHandle, saves = savesData, runner = runner
        return sensors.subscribeAccelerometer { [weak self] batch in
            runner.addAccelerometer(batch)
            let count = batch.count
            guard saves else {
                Task { @MainActor in self?.accelCount += count }
                return
            }
            var data = Data(capacity: batch.count * PuttCapture.AccelSample.size)
            for reading in batch {
                let a = reading.acceleration
                PuttCapture.AccelSample(t: reading.timestamp - startUptime, x: Float(a.x), y: Float(a.y), z: Float(a.z))
                    .append(to: &data)
            }
            let bytes = data
            io.async {
                Self.write(bytes, to: handle, name: "accelerometer")
                Task { @MainActor in self?.accelCount += count }
            }
        }
    }

    private func subscribeDeviceMotion(startUptime: Double) -> SensorInputs.Subscription {
        let io = io, handle = motionHandle, saves = savesData, runner = runner
        return sensors.subscribeDeviceMotion { [weak self] batch in
            runner.addMotion(batch)
            let count = batch.count
            guard saves else {
                Task { @MainActor in self?.motionCount += count }
                return
            }
            var data = Data(capacity: batch.count * PuttCapture.MotionSample.size)
            for motion in batch {
                let r = motion.rotationRate, u = motion.userAcceleration, g = motion.gravity, q = motion.attitude.quaternion
                PuttCapture.MotionSample(t: motion.timestamp - startUptime, values: [
                    Float(r.x), Float(r.y), Float(r.z),
                    Float(u.x), Float(u.y), Float(u.z),
                    Float(g.x), Float(g.y), Float(g.z),
                    Float(q.x), Float(q.y), Float(q.z), Float(q.w)
                ]).append(to: &data)
            }
            let bytes = data
            io.async {
                Self.write(bytes, to: handle, name: "device motion")
                Task { @MainActor in self?.motionCount += count }
            }
        }
    }

    private func subscribeMicrophone(in directory: URL?, startUptime: Double) -> SensorInputs.Subscription {
        let writer = CaptureAudioWriter(url: directory?.appendingPathComponent(PuttCapture.audioFile), captureStartUptime: startUptime)
        audioWriter = writer
        let runner = runner
        return sensors.subscribeMicrophone { buffer, hostSeconds in
            runner.addAudio(MicrophoneInput.samples(buffer), hostSeconds: hostSeconds, sampleRate: buffer.format.sampleRate)
            writer.write(buffer, hostSeconds: hostSeconds)
        }
    }

    private nonisolated static func write(_ data: Data, to handle: FileHandle?, name: String) {
        do {
            try handle?.write(contentsOf: data)
        } catch {
            Log.puttLab.error("Could not write \(name) data: \(String(describing: error))")
        }
    }

    // MARK: - Marks

    /// Records that a stroke with this label just happened. The tap itself is not a stroke.
    func mark(_ label: PuttCapture.MarkLabel) {
        guard state == .recording, let startUptime = meta?.startUptime else { return }
        sensors.tapped()
        let mark = PuttCapture.Mark(t: Uptime.now - startUptime, label: label, date: Date())
        meta?.marks.append(mark)
        let handle = marksHandle
        io.async {
            Self.write(Data((mark.csvLine + "\n").utf8), to: handle, name: "marks")
        }
        Log.puttLab.notice("Mark \(label.rawValue) at \(mark.t) s")
        WKInterfaceDevice.current().play(.success)
    }

    /// Takes back the last mark, tapped by mistake. The marks file is written again without it.
    func undoLastMark() {
        guard state == .recording, let removed = meta?.marks.popLast() else { return }
        sensors.tapped()
        let lines = [PuttCapture.Mark.csvHeader] + (meta?.marks.map(\.csvLine) ?? [])
        let handle = marksHandle
        io.async {
            do {
                try handle?.truncate(atOffset: 0)
                try handle?.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
            } catch {
                Log.puttLab.error("Could not rewrite the marks: \(String(describing: error))")
            }
        }
        Log.puttLab.notice("Undid mark \(removed.label.rawValue) at \(removed.t) s")
        WKInterfaceDevice.current().play(.click)
    }

    // MARK: - Stop

    /// Stops recording and sends the capture to the phone. Also cancels a start still waiting.
    func stop() {
        switch state {
        case .idle:
            return
        case .starting:
            Log.puttLab.notice("Putt capture cancelled before recording")
            cleanUp(endWorkout: !isRoundActive())
        case .recording:
            finishRecording()
        }
    }

    private func finishRecording() {
        guard var meta, let directory else { return }
        sensors.tapped()
        for subscription in subscriptions {
            subscription.cancel()
        }
        subscriptions = []
        audioWriter?.close()
        meta.endDate = Date()
        meta.duration = Uptime.now - meta.startUptime
        meta.audio = audioWriter?.audio
        meta.audioFrames = audioWriter?.frameCount ?? 0
        meta.endBattery = Self.batteryLevel
        audioWriter = nil
        let finalMeta = meta
        self.meta = nil
        self.directory = nil
        cleanUp(endWorkout: !isRoundActive())
        // The stroke still open in the detector is reported first, so it reaches contacts.csv
        runner.stop { [weak self] in
            Task { @MainActor in self?.closeFiles(meta: finalMeta, directory: directory) }
        }
    }

    private func closeFiles(meta: PuttCapture.Meta, directory: URL) {
        let accelHandle = accelHandle, motionHandle = motionHandle, marksHandle = marksHandle, contactsHandle = contactsHandle
        self.accelHandle = nil
        self.motionHandle = nil
        self.marksHandle = nil
        self.contactsHandle = nil
        captureStartUptime = nil
        // The counts are final once every queued write is done
        io.async { [weak self] in
            try? accelHandle?.close()
            try? motionHandle?.close()
            try? marksHandle?.close()
            try? contactsHandle?.close()
            Task { @MainActor in
                guard let self else { return }
                var meta = meta
                meta.accelCount = self.accelCount
                meta.motionCount = self.motionCount
                do {
                    try meta.json().write(to: directory.appendingPathComponent(PuttCapture.metaFile))
                } catch {
                    Log.puttLab.error("Could not write the capture's details: \(String(describing: error))")
                }
                Log.puttLab.notice("Putt capture \(meta.id) stopped after \(meta.duration ?? 0) s: \(meta.accelCount) accelerometer, \(meta.motionCount) motion, \(meta.audioFrames) audio frames, \(meta.marks.count) marks, \(self.contactCount) contacts")
                self.uploader.enqueue(directory)
            }
        }
    }

    /// Leaves the file handles alone: a stopped recording closes them once the last contact is in.
    private func cleanUp(endWorkout: Bool) {
        state = .idle
        if endWorkout {
            workouts.stop()
        }
    }
}
