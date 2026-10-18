import AVFAudio
import CoreLocation
import CoreMotion
import Foundation
import os

/// Writes one segment of a putt capture: the files in `PuttCapture.files`, in one folder, times
/// in seconds since the segment started on the uptime clock. Sensor batches come in on the sensors' own threads
/// and are encoded there; every file write happens on the writer's own queue, which is also
/// where the marks and the counts live. `finish` closes the files and completes `meta.json`.
final class CaptureWriter: @unchecked Sendable {
    let directory: URL
    let startUptime: Double
    /// Read with `startUptime`, so a date goes on the segment's clock by it.
    let startDate: Date
    /// Readings and audio are written. Off for a battery test: only the counts are kept.
    let savesData: Bool

    private let io = DispatchQueue(label: "golf.spot.SpotGolf.captureWriter", qos: .utility)
    // Touched only on `io`
    private var meta: PuttCapture.Meta
    private var accelHandle: FileHandle?
    private var motionHandle: FileHandle?
    private var marksHandle: FileHandle?
    private var contactsHandle: FileHandle?
    private var candidatesHandle: FileHandle?
    private var eventsHandle: FileHandle?
    private var locationsHandle: FileHandle?
    private var audioBuffersHandle: FileHandle?
    private var accelCount = 0
    private var motionCount = 0
    private var contactCount = 0
    private var finished = false
    private let audio: CaptureAudioWriter?

    /// Creates the segment's folder and files. `meta` is written as it is, so it should carry
    /// the capture, round, hole and segment already.
    init(directory: URL, meta: PuttCapture.Meta, savesData: Bool, microphone: Bool) throws {
        self.directory = directory
        self.meta = meta
        startUptime = meta.startUptime
        startDate = meta.startDate
        self.savesData = savesData
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if savesData {
            accelHandle = try Self.createFile(directory.appendingPathComponent(PuttCapture.accelFile))
            motionHandle = try Self.createFile(directory.appendingPathComponent(PuttCapture.motionFile))
        }
        marksHandle = try Self.createFile(directory.appendingPathComponent(PuttCapture.marksFile),
                                          header: PuttCapture.Mark.csvHeader + "\n")
        contactsHandle = try Self.createFile(directory.appendingPathComponent(PuttCapture.contactsFile),
                                             header: PuttCapture.contactsHeader + "\n")
        candidatesHandle = try Self.createFile(directory.appendingPathComponent(PuttCapture.candidatesFile),
                                               header: PuttCapture.candidatesHeader + "\n")
        eventsHandle = try Self.createFile(directory.appendingPathComponent(PuttCapture.eventsFile),
                                           header: PuttCapture.eventsHeader + "\n")
        locationsHandle = try Self.createFile(directory.appendingPathComponent(PuttCapture.locationsFile),
                                              header: PuttCapture.locationsHeader + "\n")
        if microphone {
            audioBuffersHandle = try Self.createFile(directory.appendingPathComponent(PuttCapture.audioBuffersFile),
                                                     header: PuttCapture.audioBuffersHeader + "\n")
        }
        try meta.json().write(to: directory.appendingPathComponent(PuttCapture.metaFile))
        audio = microphone
            ? CaptureAudioWriter(url: savesData ? directory.appendingPathComponent(PuttCapture.audioFile) : nil,
                                 captureStartUptime: meta.startUptime)
            : nil
    }

    /// A new file holding `header`, open for writing after it.
    private static func createFile(_ url: URL, header: String = "") throws -> FileHandle {
        try Data(header.utf8).write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        return handle
    }

    // MARK: - Sensor data, on the sensors' threads

    func add(accelerometer batch: [CMAccelerometerData]) {
        let count = batch.count
        guard savesData else {
            io.async { self.accelCount += count }
            return
        }
        var data = Data(capacity: count * PuttCapture.AccelSample.size)
        for reading in batch {
            let a = reading.acceleration
            PuttCapture.AccelSample(t: reading.timestamp - startUptime, x: Float(a.x), y: Float(a.y), z: Float(a.z))
                .append(to: &data)
        }
        let bytes = data
        io.async {
            self.write(bytes, to: self.accelHandle, name: "accelerometer")
            self.accelCount += count
        }
    }

    func add(motion batch: [CMDeviceMotion]) {
        let count = batch.count
        guard savesData else {
            io.async { self.motionCount += count }
            return
        }
        var data = Data(capacity: count * PuttCapture.MotionSample.size)
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
            self.write(bytes, to: self.motionHandle, name: "device motion")
            self.motionCount += count
        }
    }

    func add(audio buffer: AVAudioPCMBuffer, hostSeconds: Double) {
        guard let audio, let first = audio.write(buffer, hostSeconds: hostSeconds) else { return }
        let line = "\(hostSeconds - startUptime),\(buffer.frameLength),\(first)\n"
        io.async {
            self.write(Data(line.utf8), to: self.audioBuffersHandle, name: "audio buffers")
        }
        // The audio's start goes into meta.json as soon as it is known, so a segment cut short
        // by a kill still says where its audio begins
        io.async {
            guard self.meta.audio == nil, let info = audio.audio else { return }
            self.meta.audio = info
            try? self.meta.json().write(to: self.directory.appendingPathComponent(PuttCapture.metaFile))
        }
    }

    // MARK: - Contacts and marks

    /// A contact the detector found, at its uptime.
    func add(contact: ContactDetector.Contact) {
        let line = "\(contact.time - startUptime),\(contact.score),\(contact.burst),\(contact.click),\(contact.turning)\n"
        io.async {
            self.write(Data(line.utf8), to: self.contactsHandle, name: "contacts")
            self.contactCount += 1
        }
    }

    /// A candidate the stroke gate judged, at its uptime. Measures the gate could not take are blank.
    func add(candidate: ContactDetector.Judged) {
        let f = candidate.features
        let fields: [String] = [
            "\(candidate.time - startUptime)", "\(candidate.burst)", "\(candidate.click)", "\(candidate.onset)", "\(candidate.score)",
            f.map { "\($0.still)" } ?? "", f.map { "\($0.tilt)" } ?? "", f.map { "\($0.backswing)" } ?? "",
            f?.returnOffset.map { "\($0)" } ?? "", candidate.passed ? "1" : "0"
        ]
        let line = fields.joined(separator: ",") + "\n"
        io.async {
            self.write(Data(line.utf8), to: self.candidatesHandle, name: "candidates")
        }
    }

    /// Something that happened on the watch, at its uptime.
    func add(event: String, value: Double, atUptime uptime: Double = Uptime.now) {
        let line = "\(uptime - startUptime),\(event),\(value)\n"
        io.async {
            self.write(Data(line.utf8), to: self.eventsHandle, name: "events")
        }
    }

    /// Something that happened on the watch at `date`, which is put on the segment's clock by
    /// the start date: the two were read together.
    func add(event: String, value: Double, at date: Date) {
        add(event: event, value: value, atUptime: startUptime + date.timeIntervalSince(startDate))
    }

    /// GPS fixes. Unknown altitude, accuracy, speed or course are blank.
    func add(locations: [CLLocation]) {
        let lines = locations.map { location -> String in
            func valid(_ value: Double, _ ok: Bool) -> String { ok ? "\(value)" : "" }
            let fields = [
                "\(location.timestamp.timeIntervalSince(startDate))",
                "\(location.coordinate.latitude)", "\(location.coordinate.longitude)",
                valid(location.altitude, location.verticalAccuracy >= 0),
                valid(location.horizontalAccuracy, location.horizontalAccuracy >= 0),
                valid(location.verticalAccuracy, location.verticalAccuracy >= 0),
                valid(location.speed, location.speed >= 0),
                valid(location.course, location.course >= 0)
            ]
            return fields.joined(separator: ",") + "\n"
        }.joined()
        io.async {
            self.write(Data(lines.utf8), to: self.locationsHandle, name: "locations")
        }
    }

    /// A stroke with this label just happened. Returns the mark as written.
    @discardableResult
    func mark(_ label: PuttCapture.MarkLabel, date: Date = Date()) -> PuttCapture.Mark {
        let mark = PuttCapture.Mark(t: Uptime.now - startUptime, label: label, date: date)
        io.async {
            self.meta.marks.append(mark)
            self.write(Data((mark.csvLine + "\n").utf8), to: self.marksHandle, name: "marks")
        }
        return mark
    }

    /// Takes back the last mark; the marks file is written again without it.
    func undoLastMark() {
        io.async {
            guard self.meta.marks.popLast() != nil else { return }
            let lines = [PuttCapture.Mark.csvHeader] + self.meta.marks.map(\.csvLine)
            do {
                try self.marksHandle?.truncate(atOffset: 0)
                try self.marksHandle?.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
            } catch {
                Log.puttLab.error("Could not rewrite the marks: \(String(describing: error))")
            }
        }
    }

    private func write(_ data: Data, to handle: FileHandle?, name: String) {
        do {
            try handle?.write(contentsOf: data)
        } catch {
            Log.puttLab.error("Could not write \(name) data: \(String(describing: error))")
        }
    }

    // MARK: - Finish

    /// Closes the files once every queued write is done and completes `meta.json`. The caller
    /// has stopped feeding the writer. `completion` gets the final details on the main actor.
    func finish(reason: PuttCapture.EndReason, battery: Double?, completion: @escaping @MainActor (PuttCapture.Meta) -> Void) {
        let endDate = Date()
        let duration = Uptime.now - startUptime
        audio?.close()
        io.async {
            guard !self.finished else { return }
            self.finished = true
            try? self.accelHandle?.close()
            try? self.motionHandle?.close()
            try? self.marksHandle?.close()
            try? self.contactsHandle?.close()
            try? self.candidatesHandle?.close()
            try? self.eventsHandle?.close()
            try? self.locationsHandle?.close()
            try? self.audioBuffersHandle?.close()
            self.meta.endDate = endDate
            self.meta.duration = duration
            self.meta.endReason = reason
            self.meta.endBattery = battery
            self.meta.audio = self.audio?.audio
            self.meta.audioFrames = self.audio?.frameCount ?? 0
            self.meta.accelCount = self.accelCount
            self.meta.motionCount = self.motionCount
            do {
                try self.meta.json().write(to: self.directory.appendingPathComponent(PuttCapture.metaFile))
            } catch {
                Log.puttLab.error("Could not write the segment's details: \(String(describing: error))")
            }
            let meta = self.meta
            let contacts = self.contactCount
            Log.puttLab.notice("Segment \(meta.segment ?? 0) of capture \(meta.captureID?.uuidString ?? meta.id.uuidString) ended (\(reason.rawValue)) after \(duration) s: \(meta.accelCount) accelerometer, \(meta.motionCount) motion, \(meta.audioFrames) audio frames, \(meta.marks.count) marks, \(contacts) contacts")
            Task { @MainActor in completion(meta) }
        }
    }

    // MARK: - Recovery

    /// Finishes every segment under `root` left open by a kill: its `meta.json` has no end.
    /// The counts come from the file sizes and the end from when the files were last written.
    static func finishUnfinished(under root: URL) {
        let manager = FileManager.default
        let captures = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for capture in captures where capture.isDirectory {
            let segments = (try? manager.contentsOfDirectory(at: capture, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for segment in segments where segment.isDirectory {
                let metaURL = segment.appendingPathComponent(PuttCapture.metaFile)
                guard let data = try? Data(contentsOf: metaURL), var meta = try? PuttCapture.Meta(json: data),
                      meta.endDate == nil else { continue }
                func size(_ name: String) -> Int {
                    (try? manager.attributesOfItem(atPath: segment.appendingPathComponent(name).path)[.size] as? Int) ?? 0
                }
                func modified(_ name: String) -> Date? {
                    try? manager.attributesOfItem(atPath: segment.appendingPathComponent(name).path)[.modificationDate] as? Date
                }
                meta.accelCount = size(PuttCapture.accelFile) / PuttCapture.AccelSample.size
                meta.motionCount = size(PuttCapture.motionFile) / PuttCapture.MotionSample.size
                if let file = try? AVAudioFile(forReading: segment.appendingPathComponent(PuttCapture.audioFile)) {
                    meta.audioFrames = Int(file.length)
                }
                let endDate = [modified(PuttCapture.accelFile), modified(PuttCapture.contactsFile), modified(PuttCapture.metaFile)]
                    .compactMap { $0 }.max() ?? Date()
                meta.endDate = endDate
                meta.duration = endDate.timeIntervalSince(meta.startDate)
                meta.endReason = .appTerminated
                do {
                    try meta.json().write(to: metaURL)
                    Log.puttLab.notice("Finished segment \(segment.lastPathComponent) of capture \(capture.lastPathComponent) left open by a kill")
                } catch {
                    Log.puttLab.error("Could not finish segment \(segment.lastPathComponent): \(String(describing: error))")
                }
            }
        }
    }
}
