import Foundation

/// A putt capture: raw sensor data recorded by the watch's Putt Lab, to study what a real putt
/// looks like. A capture is a folder of segments, one per green visit in a round or a single
/// one outside a round; each segment holds the files below. See `plans/2026-10-06-putt-capture.md`
/// for the files and their layout and `plans/2026-10-12-putt-lab-in-rounds.md` for segments.
enum PuttCapture {
    static let version = 3

    /// The folder under Documents that holds every capture.
    static let directoryName = "putt-captures"

    static let metaFile = "meta.json"
    static let marksFile = "marks.csv"
    static let accelFile = "accel.bin"
    static let motionFile = "motion.bin"
    static let audioFile = "audio.wav"
    /// The contacts `ContactDetector` found as the capture ran, for checking against the marks.
    static let contactsFile = "contacts.csv"
    static let contactsHeader = "t,score,burst,click,turning"
    /// Every candidate the detector judged with `StrokeGate`, passed or not, with what the gate
    /// measured, so the gate's limits can be checked against the marks. Version 3 on.
    static let candidatesFile = "candidates.csv"
    static let candidatesHeader = "t,burst,click,onset,score,still,tilt,backswing,returnOffset,passed"
    /// Each microphone buffer: its capture time, length and first frame in `audio.wav`, so a mic
    /// stall shows as a gap. Version 3 on.
    static let audioBuffersFile = "audio-buffers.csv"
    static let audioBuffersHeader = "t,frames,firstFrame"
    /// What happened on the watch while recording: taps on the app's buttons, haptics, display
    /// hole changes, swings, and the workout's and sensors' stream events. Version 3 on.
    static let eventsFile = "events.csv"
    static let eventsHeader = "t,event,value"
    /// The watch's GPS fixes. Version 3 on.
    static let locationsFile = "locations.csv"
    static let locationsHeader = "t,latitude,longitude,altitude,horizontalAccuracy,verticalAccuracy,speed,course"
    /// Every file a segment can hold.
    static let files = [metaFile, marksFile, contactsFile, candidatesFile, eventsFile, locationsFile, accelFile, motionFile,
                        audioFile, audioBuffersFile]

    /// A segment's folder name in its capture: "001-hole1".
    static func segmentFolder(_ segment: Int, hole: Int) -> String {
        String(format: "%03d-hole%d", segment, hole)
    }

    /// Why a segment ended.
    enum EndReason: String, Codable {
        /// Stop on the Putt Lab page.
        case stopped
        case leftGreen
        case holeAdvanced
        case workoutStopped
        case roundEnded
        /// The app was killed with the segment open; the next launch finished it from the file sizes.
        case appTerminated
    }

    /// What the player labelled a stroke with, tapped after the stroke.
    enum MarkLabel: String, Codable, CaseIterable {
        /// The ball was struck.
        case putt
        /// A practice stroke with no ball.
        case practice
        /// A practice stroke with no ball that hit the ground.
        case ground

        /// The name on the watch's button.
        var title: String {
            switch self {
            case .putt: String(localized: "Putt")
            case .practice: String(localized: "Practice")
            case .ground: String(localized: "Practice ground")
            }
        }
    }

    struct Mark: Codable, Equatable {
        /// Seconds since the capture started.
        let t: Double
        let label: MarkLabel
        let date: Date

        static let csvHeader = "t,label,date"

        var csvLine: String {
            "\(t),\(label.rawValue),\(PuttCapture.dateFormat.format(date))"
        }
    }

    struct Audio: Codable, Equatable {
        let sampleRate: Double
        let channels: Int
        /// Capture time of sample 0, from the first buffer's host time.
        let startTime: Double
        /// The first buffer's host time in seconds, on the uptime clock.
        let startHostTime: Double
        /// Uptime read in the first buffer's callback. Within a buffer of `startHostTime` when
        /// the two clocks agree.
        let startUptime: Double
    }

    struct Meta: Codable, Equatable {
        let id: UUID
        var version = PuttCapture.version
        let startDate: Date
        /// `ProcessInfo.systemUptime` at the start: the clock the sensor timestamps use.
        let startUptime: Double
        var endDate: Date?
        var duration: Double?
        var audio: Audio?
        var accelCount = 0
        var motionCount = 0
        var audioFrames = 0
        /// Battery level, 0 to 1, at the start and end, when the device reports it.
        var startBattery: Double?
        var endBattery: Double?
        /// The mic was on.
        var microphone = true
        /// Readings and audio were written. Off for a battery test, which runs the sensors
        /// and the scoring math and keeps only the counts and the battery levels.
        var savesData = true
        var marks: [Mark] = []
        /// The capture folder the segment is in. Absent in version 1 captures, which were one segment.
        var captureID: UUID?
        /// The round the capture was recorded in. Absent outside a round.
        var roundID: UUID?
        /// The display hole when the segment started, 1-based; 0 outside a round.
        var hole: Int?
        /// The segment's number in its capture, from 1.
        var segment: Int?
        var endReason: EndReason?
        /// The wrist the watch is worn on, "left" or "right", as set on the watch. Version 3 on.
        var wristLocation: String?
        /// The side the Digital Crown is on, "left" or "right", as the wearer sees it. Version 3 on.
        var crownOrientation: String?
        /// The round's Green Zone in meters when the segment started. Absent outside a round.
        var greenZone: Double?

        /// Dates keep their milliseconds, so marks match the stream. Version 2 cut them to seconds.
        func json() throws -> Data {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .custom { date, encoder in
                var container = encoder.singleValueContainer()
                try container.encode(PuttCapture.dateFormat.format(date))
            }
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(self)
        }

        init(id: UUID = UUID(), startDate: Date, startUptime: Double) {
            self.id = id
            self.startDate = startDate
            self.startUptime = startUptime
        }

        /// Reads dates with or without milliseconds.
        init(json: Data) throws {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let text = try decoder.singleValueContainer().decode(String.self)
                if let date = (try? PuttCapture.dateFormat.parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text)) {
                    return date
                }
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a date: \(text)"))
            }
            self = try decoder.decode(Meta.self, from: json)
        }

        /// Captures from before `microphone` and `savesData` were written have both on.
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(UUID.self, forKey: .id)
            version = try values.decode(Int.self, forKey: .version)
            startDate = try values.decode(Date.self, forKey: .startDate)
            startUptime = try values.decode(Double.self, forKey: .startUptime)
            endDate = try values.decodeIfPresent(Date.self, forKey: .endDate)
            duration = try values.decodeIfPresent(Double.self, forKey: .duration)
            audio = try values.decodeIfPresent(Audio.self, forKey: .audio)
            accelCount = try values.decode(Int.self, forKey: .accelCount)
            motionCount = try values.decode(Int.self, forKey: .motionCount)
            audioFrames = try values.decode(Int.self, forKey: .audioFrames)
            startBattery = try values.decodeIfPresent(Double.self, forKey: .startBattery)
            endBattery = try values.decodeIfPresent(Double.self, forKey: .endBattery)
            microphone = try values.decodeIfPresent(Bool.self, forKey: .microphone) ?? true
            savesData = try values.decodeIfPresent(Bool.self, forKey: .savesData) ?? true
            marks = try values.decode([Mark].self, forKey: .marks)
            captureID = try values.decodeIfPresent(UUID.self, forKey: .captureID)
            roundID = try values.decodeIfPresent(UUID.self, forKey: .roundID)
            hole = try values.decodeIfPresent(Int.self, forKey: .hole)
            segment = try values.decodeIfPresent(Int.self, forKey: .segment)
            endReason = try values.decodeIfPresent(EndReason.self, forKey: .endReason)
            wristLocation = try values.decodeIfPresent(String.self, forKey: .wristLocation)
            crownOrientation = try values.decodeIfPresent(String.self, forKey: .crownOrientation)
            greenZone = try values.decodeIfPresent(Double.self, forKey: .greenZone)
        }
    }

    /// One accelerometer reading: `t` Float64, then `x y z` Float32 in g. Little-endian, 20 bytes.
    struct AccelSample: Equatable {
        static let size = 20

        let t: Double
        let x: Float
        let y: Float
        let z: Float

        func append(to data: inout Data) {
            data.append(littleEndian: t.bitPattern)
            data.append(littleEndian: x.bitPattern)
            data.append(littleEndian: y.bitPattern)
            data.append(littleEndian: z.bitPattern)
        }

        init(t: Double, x: Float, y: Float, z: Float) {
            self.t = t
            self.x = x
            self.y = y
            self.z = z
        }

        init?(record: Data) {
            guard record.count == Self.size else { return nil }
            let record = Data(record)
            t = Double(bitPattern: record.littleEndianInteger(at: 0))
            x = Float(bitPattern: record.littleEndianInteger(at: 8))
            y = Float(bitPattern: record.littleEndianInteger(at: 12))
            z = Float(bitPattern: record.littleEndianInteger(at: 16))
        }
    }

    /// One device motion reading: `t` Float64, then 13 Float32: rotation rate `x y z` in rad/s,
    /// user acceleration `x y z` in g, gravity `x y z` in g, attitude quaternion `x y z w`.
    /// Little-endian, 60 bytes.
    struct MotionSample: Equatable {
        static let size = 60
        static let valueCount = 13

        let t: Double
        let values: [Float]

        func append(to data: inout Data) {
            data.append(littleEndian: t.bitPattern)
            for value in values {
                data.append(littleEndian: value.bitPattern)
            }
        }

        init(t: Double, values: [Float]) {
            precondition(values.count == Self.valueCount)
            self.t = t
            self.values = values
        }

        init?(record: Data) {
            guard record.count == Self.size else { return nil }
            let record = Data(record)
            t = Double(bitPattern: record.littleEndianInteger(at: 0))
            values = (0..<Self.valueCount).map { Float(bitPattern: record.littleEndianInteger(at: 8 + $0 * 4)) }
        }
    }

    /// "2026-10-08T20:16:02.123Z"
    static let dateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}
