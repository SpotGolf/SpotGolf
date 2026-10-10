import Foundation

/// Every message sent between the phone and the watch. Each is encoded on its own, and
/// replies are messages too.
enum SyncMessage: Codable, Equatable {
    case startRound(StartRound)
    case startRoundAck(StartRoundAck)
    case startRoundRefused(StartRoundRefused)
    case cancelRound(CancelRound)
    case endRequest(EndRequest)
    case endRound(EndRound)
    case endAck(EndAck)
    case streamBatch(StreamBatch)
    case streamAck(StreamAck)
    case holeTimeline(HoleTimelineMessage)
    case displayHole(DisplayHoleMessage)
    case pins(PinsMessage)
    case strokes(StrokesSnapshot)
    /// The latest timeline, display hole, pins and strokes, sent as application context.
    case context(SyncContext)
    /// Part of a message too large for one send.
    case chunk(SyncChunk)
}

/// Phone → watch. The watch replies `StartRoundAck` once the round is active, or
/// `StartRoundRefused` when its app is not `version` or it is missing permissions.
struct StartRound: Codable, Equatable {
    let roundID: UUID
    let date: Date
    /// `CourseSelection.trimmed`, JSON, gzipped.
    let course: Data
    let holeTimeline: [HoleStart]
    let displayHole: DisplayHole
    let pins: [PinLocation]
    let strokes: StrokesSnapshot
    /// The first stream index for the round: nonzero when an ended round is resumed.
    let streamBase: Int
    /// The phone app's version. The watch app must be the same, or it refuses the round.
    let version: String
    /// The first `seq` for the watch's log lines: the phone's count of them, nonzero on a resume.
    let logBase: Int
    /// The phone's Debug Logging setting, which the watch follows.
    let debugLogging: Bool

    init(roundID: UUID, date: Date, course: Data, holeTimeline: [HoleStart], displayHole: DisplayHole,
         pins: [PinLocation], strokes: StrokesSnapshot, streamBase: Int, version: String,
         logBase: Int = 0, debugLogging: Bool = false) {
        self.roundID = roundID
        self.date = date
        self.course = course
        self.holeTimeline = holeTimeline
        self.displayHole = displayHole
        self.pins = pins
        self.strokes = strokes
        self.streamBase = streamBase
        self.version = version
        self.logBase = logBase
        self.debugLogging = debugLogging
    }
}

extension StartRound {
    /// A phone from before versions were checked sends none; it is never the watch's. One from
    /// before the app log sends no log base or debug setting.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        roundID = try values.decode(UUID.self, forKey: .roundID)
        date = try values.decode(Date.self, forKey: .date)
        course = try values.decode(Data.self, forKey: .course)
        holeTimeline = try values.decode([HoleStart].self, forKey: .holeTimeline)
        displayHole = try values.decode(DisplayHole.self, forKey: .displayHole)
        pins = try values.decode([PinLocation].self, forKey: .pins)
        strokes = try values.decode(StrokesSnapshot.self, forKey: .strokes)
        streamBase = try values.decode(Int.self, forKey: .streamBase)
        version = try values.decodeIfPresent(String.self, forKey: .version) ?? ""
        logBase = try values.decodeIfPresent(Int.self, forKey: .logBase) ?? 0
        debugLogging = try values.decodeIfPresent(Bool.self, forKey: .debugLogging) ?? false
    }
}

struct StartRoundAck: Codable, Equatable {
    let roundID: UUID
}

/// Watch → phone, in place of `StartRoundAck`. The watch can't record the round.
struct StartRoundRefused: Codable, Equatable {
    enum Reason: Equatable {
        /// The watch can't record until these permissions are granted on it.
        case missingPermissions([AppPermission])
        /// The watch app is not the phone app's version: the watch app must be updated first.
        case versionMismatch(watchVersion: String)
    }

    let roundID: UUID
    let reason: Reason

    init(roundID: UUID, reason: Reason) {
        self.roundID = roundID
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case roundID, missing, watchVersion
    }

    /// A refusal from before versions were checked has only `missing`. A permission this build
    /// does not know, from a newer watch, is left out rather than making the whole refusal
    /// unreadable.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        roundID = try values.decode(UUID.self, forKey: .roundID)
        if let watchVersion = try values.decodeIfPresent(String.self, forKey: .watchVersion) {
            reason = .versionMismatch(watchVersion: watchVersion)
        } else {
            let names = try values.decodeIfPresent([String].self, forKey: .missing) ?? []
            reason = .missingPermissions(names.compactMap(AppPermission.init(rawValue:)))
        }
    }

    /// `missing` is always written, so a phone from before versions were checked still reads it.
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(roundID, forKey: .roundID)
        switch reason {
        case .missingPermissions(let missing):
            try values.encode(missing, forKey: .missing)
        case .versionMismatch(let watchVersion):
            try values.encode([AppPermission](), forKey: .missing)
            try values.encode(watchVersion, forKey: .watchVersion)
        }
    }
}

/// Phone → watch. The phone gave up starting the round.
struct CancelRound: Codable, Equatable {
    let roundID: UUID
}

/// Phone → watch. The phone ended the round; the watch replies `EndAck`.
struct EndRequest: Codable, Equatable {
    let roundID: UUID
    let endedAt: Date
}

/// Watch → phone. The watch ended the round; the phone replies `EndAck`.
struct EndRound: Codable, Equatable {
    let roundID: UUID
    let endedAt: Date
    /// The index of the last stream record, or nil when the watch recorded nothing.
    let lastSeq: Int?
}

struct EndAck: Codable, Equatable {
    let roundID: UUID
    /// From the watch: its last stream record. From the phone: not used.
    let lastSeq: Int?
}

/// Watch → phone. Stream records `from..<from + count`, and the watch's log lines
/// `logsFrom..<logsFrom + logs.count`. Empty records and logs ask for the phone's `have`
/// and `haveLogs`. The log fields are optional, so a batch from before the app log decodes.
struct StreamBatch: Codable, Equatable {
    let roundID: UUID
    let from: Int
    /// `StreamRecord` records back to back.
    let records: Data
    let logsFrom: Int?
    let logs: [LogLine]?

    init(roundID: UUID, from: Int, records: Data, logsFrom: Int? = nil, logs: [LogLine]? = nil) {
        self.roundID = roundID
        self.from = from
        self.records = records
        self.logsFrom = logsFrom
        self.logs = logs
    }
}

/// Phone → watch. The phone holds records `0..<have` and log lines `0..<haveLogs` with no gaps.
struct StreamAck: Codable, Equatable {
    let roundID: UUID
    /// Nil when the phone does not know the round; the watch then deletes its stream.
    let have: Int?
    /// Nil from a phone from before the app log, which the watch reads as having every line.
    let haveLogs: Int?

    init(roundID: UUID, have: Int?, haveLogs: Int? = nil) {
        self.roundID = roundID
        self.have = have
        self.haveLogs = haveLogs
    }
}

struct HoleTimelineMessage: Codable, Equatable {
    let roundID: UUID
    let entries: [HoleStart]
}

/// Both ways. The hole both devices show; the later change wins.
struct DisplayHoleMessage: Codable, Equatable {
    let roundID: UUID
    let displayHole: DisplayHole
}

/// Both ways. Every pin in the round; per hole, the later one wins.
struct PinsMessage: Codable, Equatable {
    let roundID: UUID
    let pins: [PinLocation]
}

/// Phone → watch. Every stroke in the round. The watch keeps the highest version.
struct StrokesSnapshot: Codable, Equatable {
    let roundID: UUID
    let version: Int
    /// Strokes per hole index.
    let holes: [[Stroke]]
}

struct SyncContext: Codable, Equatable {
    let timeline: HoleTimelineMessage?
    let displayHole: DisplayHoleMessage?
    let pins: PinsMessage?
    let strokes: StrokesSnapshot?
}

struct SyncChunk: Codable, Equatable {
    let transferID: UUID
    let index: Int
    let totalChunks: Int
    let data: Data
}

extension SyncMessage {
    /// The kind of message, for logs. The whole message can be large.
    var name: String {
        switch self {
        case .startRound: "startRound"
        case .startRoundAck: "startRoundAck"
        case .startRoundRefused: "startRoundRefused"
        case .cancelRound: "cancelRound"
        case .endRequest: "endRequest"
        case .endRound: "endRound"
        case .endAck: "endAck"
        case .streamBatch: "streamBatch"
        case .streamAck: "streamAck"
        case .holeTimeline: "holeTimeline"
        case .displayHole: "displayHole"
        case .pins: "pins"
        case .strokes: "strokes"
        case .context: "context"
        case .chunk: "chunk"
        }
    }
}
