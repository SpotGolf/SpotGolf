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

/// Phone → watch. The watch replies `StartRoundAck` once the round is active.
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
}

struct StartRoundAck: Codable, Equatable {
    let roundID: UUID
}

/// Watch → phone, in place of `StartRoundAck`. The watch can't record the round until these
/// permissions are granted.
struct StartRoundRefused: Codable, Equatable {
    let roundID: UUID
    let missing: [AppPermission]

    init(roundID: UUID, missing: [AppPermission]) {
        self.roundID = roundID
        self.missing = missing
    }

    /// A permission this build does not know, from a newer watch, is left out rather than
    /// making the whole refusal unreadable.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        roundID = try values.decode(UUID.self, forKey: .roundID)
        missing = try values.decode([String].self, forKey: .missing).compactMap(AppPermission.init(rawValue:))
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

/// Watch → phone. Stream records `from..<from + count`. Empty records ask for the phone's `have`.
struct StreamBatch: Codable, Equatable {
    let roundID: UUID
    let from: Int
    /// `StreamRecord` records back to back.
    let records: Data
}

/// Phone → watch. The phone holds records `0..<have` with no gaps.
struct StreamAck: Codable, Equatable {
    let roundID: UUID
    /// Nil when the phone does not know the round; the watch then deletes its stream.
    let have: Int?
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
