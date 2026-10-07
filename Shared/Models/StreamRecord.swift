import Foundation

/// One record in a round's stream from the watch: a GPS fix, a swing or a contact, in the
/// order the watch recorded them. A record's position in the stream is its index.
enum StreamRecord: Equatable {
    case fix(TrackPoint)
    /// A swing the watch detected: a `StrokeSuggestion` with a time and peak force only.
    case swing(StrokeSuggestion)
    /// Ball contact the watch heard and felt.
    case contact(ContactEvent)

    /// Bytes per record: a kind byte, then 24 bytes of data.
    static let size = 1 + TrackPoint.recordSize

    private static let fixKind: UInt8 = 0
    private static let swingKind: UInt8 = 1
    private static let contactKind: UInt8 = 2

    var timestamp: Date {
        switch self {
        case .fix(let point): point.timestamp
        case .swing(let swing): swing.timestamp
        case .contact(let contact): contact.timestamp
        }
    }

    /// Fix: kind 0, then the `TrackPoint` record. Swing: kind 1, milliseconds since 1970
    /// (Int64), peak force in g (Float32), then 12 zero bytes. Contact: kind 2, milliseconds
    /// since 1970 (Int64), then score, burst, click and turning (Float32 each). Little-endian.
    var record: Data {
        var data = Data(capacity: Self.size)
        switch self {
        case .fix(let point):
            data.append(Self.fixKind)
            data.append(point.record)
        case .swing(let swing):
            data.append(Self.swingKind)
            data.append(littleEndian: Int64((swing.timestamp.timeIntervalSince1970 * 1000).rounded()))
            data.append(littleEndian: (swing.peakG ?? 0).bitPattern)
            data.append(Data(count: Self.size - data.count))
        case .contact(let contact):
            data.append(Self.contactKind)
            data.append(littleEndian: Int64((contact.timestamp.timeIntervalSince1970 * 1000).rounded()))
            data.append(littleEndian: contact.score.bitPattern)
            data.append(littleEndian: contact.burst.bitPattern)
            data.append(littleEndian: contact.click.bitPattern)
            data.append(littleEndian: contact.turning.bitPattern)
        }
        return data
    }

    /// Returns nil unless `record` is exactly one record of a known kind.
    init?(record: Data) {
        guard record.count == Self.size else { return nil }
        let body = record.dropFirst()
        switch record[record.startIndex] {
        case Self.fixKind:
            guard let point = TrackPoint(record: Data(body)) else { return nil }
            self = .fix(point)
        case Self.swingKind:
            let body = Data(body)
            let milliseconds: Int64 = body.littleEndianInteger(at: 0)
            let peakBits: UInt32 = body.littleEndianInteger(at: 8)
            self = .swing(.swing(at: Date(timeIntervalSince1970: Double(milliseconds) / 1000),
                                 peakG: Float(bitPattern: peakBits)))
        case Self.contactKind:
            let body = Data(body)
            let milliseconds: Int64 = body.littleEndianInteger(at: 0)
            func float(_ offset: Int) -> Float { Float(bitPattern: body.littleEndianInteger(at: offset) as UInt32) }
            self = .contact(ContactEvent(timestamp: Date(timeIntervalSince1970: Double(milliseconds) / 1000),
                                         score: float(8), burst: float(12), click: float(16), turning: float(20)))
        default:
            return nil
        }
    }

    /// Splits back-to-back records. A partial record at the end is dropped.
    static func records(in data: Data) -> [StreamRecord] {
        let count = data.count / size
        return (0..<count).compactMap { index in
            let start = data.startIndex + index * size
            return StreamRecord(record: data[start..<(start + size)])
        }
    }

    static func data(for records: [StreamRecord]) -> Data {
        var data = Data(capacity: records.count * size)
        for record in records {
            data.append(record.record)
        }
        return data
    }
}
