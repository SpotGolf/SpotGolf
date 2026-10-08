import Foundation

/// A putt capture: raw sensor data recorded on the watch's Putt Lab page, to study what a
/// real putt looks like. See `plans/2026-10-06-putt-capture.md` for the files and their layout.
enum PuttCapture {
    static let version = 1

    static let metaFile = "meta.json"
    static let marksFile = "marks.csv"
    static let accelFile = "accel.bin"
    static let motionFile = "motion.bin"
    static let audioFile = "audio.wav"
    /// The contacts `ContactDetector` found as the capture ran, for checking against the marks.
    static let contactsFile = "contacts.csv"
    static let contactsHeader = "t,score,burst,click,turning"
    /// Every file a capture can hold, in the order they are sent to the phone: small ones first.
    static let files = [metaFile, marksFile, contactsFile, accelFile, motionFile, audioFile]

    /// Keys of the metadata sent with each file transfer.
    static let captureKey = "capture"
    static let fileKey = "file"

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

        func json() throws -> Data {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(self)
        }

        init(id: UUID = UUID(), startDate: Date, startUptime: Double) {
            self.id = id
            self.startDate = startDate
            self.startUptime = startUptime
        }

        init(json: Data) throws {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
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
