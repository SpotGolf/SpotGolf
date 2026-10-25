import Foundation

/// A round's stream packed small for iCloud: each 25-byte `StreamRecord` is stored as its change
/// from the previous record of the same kind, in a few bytes. Lossless: decoding gives back the
/// same bytes. The watch link and the stores keep the 25-byte records.
/// See plans/2026-10-22-cloudkit-sync.md.
///
/// Layout: a version byte, a varint record count, then per record its kind byte and five
/// zigzag varints: the change in the Int64 time, then in each of the four Int32 words after it.
enum StreamEncoding {
    static let version: UInt8 = 1

    enum DecodeError: Error, Equatable {
        /// Written by a newer version of the app.
        case newerVersion(UInt8)
        /// Cut off, or not this format.
        case corrupt
    }

    // The time and four words that follow a record's kind byte
    private struct Fields {
        var time: Int64 = 0
        var words: (Int32, Int32, Int32, Int32) = (0, 0, 0, 0)
    }

    /// Encodes whole 25-byte records. A partial record at the end is left out.
    static func encode(_ records: Data) -> Data {
        let count = records.count / StreamRecord.size
        var out = Data([version])
        out.reserveCapacity(count * 8 + 8)
        appendVarint(UInt64(count), to: &out)
        var previous: [UInt8: Fields] = [:]
        records.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for index in 0..<count {
                let start = index * StreamRecord.size
                let kind = bytes[start]
                let fields = Fields(time: Int64(littleEndian: bytes.loadUnaligned(fromByteOffset: start + 1, as: Int64.self)),
                                    words: (word(bytes, start + 9), word(bytes, start + 13),
                                            word(bytes, start + 17), word(bytes, start + 21)))
                let last = previous[kind] ?? Fields()
                out.append(kind)
                appendVarint(zigzag(fields.time &- last.time), to: &out)
                appendVarint(UInt64(zigzag(fields.words.0 &- last.words.0)), to: &out)
                appendVarint(UInt64(zigzag(fields.words.1 &- last.words.1)), to: &out)
                appendVarint(UInt64(zigzag(fields.words.2 &- last.words.2)), to: &out)
                appendVarint(UInt64(zigzag(fields.words.3 &- last.words.3)), to: &out)
                previous[kind] = fields
            }
        }
        return out
    }

    /// The 25-byte records, in order.
    static func decode(_ data: Data) throws -> Data {
        var reader = Reader(data: data)
        let version = try reader.byte()
        guard version <= Self.version else { throw DecodeError.newerVersion(version) }
        guard version == Self.version else { throw DecodeError.corrupt }
        let count = try reader.varint()
        // Each record takes at least 6 bytes, so a larger count is not this format
        guard count <= UInt64(data.count) else { throw DecodeError.corrupt }
        var out = Data(capacity: Int(count) * StreamRecord.size)
        var previous: [UInt8: Fields] = [:]
        for _ in 0..<count {
            let kind = try reader.byte()
            var fields = previous[kind] ?? Fields()
            fields.time = fields.time &+ unzigzag(try reader.varint())
            fields.words.0 = fields.words.0 &+ (try unzigzag32(reader.varint()))
            fields.words.1 = fields.words.1 &+ (try unzigzag32(reader.varint()))
            fields.words.2 = fields.words.2 &+ (try unzigzag32(reader.varint()))
            fields.words.3 = fields.words.3 &+ (try unzigzag32(reader.varint()))
            previous[kind] = fields
            out.append(kind)
            out.append(littleEndian: fields.time)
            out.append(littleEndian: fields.words.0)
            out.append(littleEndian: fields.words.1)
            out.append(littleEndian: fields.words.2)
            out.append(littleEndian: fields.words.3)
        }
        guard reader.isAtEnd else { throw DecodeError.corrupt }
        return out
    }

    private static func word(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> Int32 {
        Int32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: Int32.self))
    }

    // Zigzag maps small negative numbers to small positive ones: 0, -1, 1, -2 → 0, 1, 2, 3
    private static func zigzag(_ value: Int64) -> UInt64 {
        UInt64(bitPattern: (value << 1) ^ (value >> 63))
    }

    private static func zigzag(_ value: Int32) -> UInt32 {
        UInt32(bitPattern: (value << 1) ^ (value >> 31))
    }

    private static func unzigzag(_ value: UInt64) -> Int64 {
        Int64(bitPattern: value >> 1) ^ -Int64(bitPattern: value & 1)
    }

    private static func unzigzag32(_ value: UInt64) throws -> Int32 {
        guard let narrow = UInt32(exactly: value) else { throw DecodeError.corrupt }
        return Int32(bitPattern: narrow >> 1) ^ -Int32(bitPattern: narrow & 1)
    }

    // 7 bits per byte, low bits first, the high bit set when more bytes follow
    private static func appendVarint(_ value: UInt64, to data: inout Data) {
        var value = value
        while value >= 0x80 {
            data.append(UInt8(value & 0x7F) | 0x80)
            value >>= 7
        }
        data.append(UInt8(value))
    }

    private struct Reader {
        let data: Data
        var offset: Int

        init(data: Data) {
            self.data = data
            offset = data.startIndex
        }

        var isAtEnd: Bool { offset == data.endIndex }

        mutating func byte() throws -> UInt8 {
            guard offset < data.endIndex else { throw DecodeError.corrupt }
            defer { offset += 1 }
            return data[offset]
        }

        mutating func varint() throws -> UInt64 {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                let byte = try byte()
                // A UInt64 takes at most 10 bytes, the last holding 1 bit
                guard shift < 64, shift < 63 || byte <= 1 else { throw DecodeError.corrupt }
                value |= UInt64(byte & 0x7F) << shift
                guard byte & 0x80 != 0 else { return value }
                shift += 7
            }
        }
    }
}
