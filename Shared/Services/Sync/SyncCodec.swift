import Foundation
import os

/// Turns messages into the dictionaries WatchConnectivity sends, and back.
/// Every message is one entry, `["m": Data]`, holding the message as a binary property list.
/// Binary plists store `Data` as raw bytes, so stream records are not inflated.
enum SyncCodec {
    static let key = "m"

    /// Messages larger than this are split into chunks. `sendMessage` allows about 65 KB.
    static let maxMessageBytes = 60_000

    // Room for the chunk's own fields around its data
    static let chunkDataBytes = maxMessageBytes - 1_000

    static func encode(_ message: SyncMessage) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(message)
    }

    static func decode(_ data: Data) throws -> SyncMessage {
        try PropertyListDecoder().decode(SyncMessage.self, from: data)
    }

    static func payload(_ message: SyncMessage) throws -> [String: Any] {
        [key: try encode(message)]
    }

    /// The message in a payload, or nil for an empty or unreadable payload.
    static func message(in payload: [String: Any]) -> SyncMessage? {
        guard let data = payload[key] as? Data else { return nil }
        do {
            return try decode(data)
        } catch {
            Log.sync.error("Could not decode message: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The payloads to send for `message`: one, or one chunk each when it is too large.
    static func payloads(for message: SyncMessage) throws -> [[String: Any]] {
        let data = try encode(message)
        guard data.count > maxMessageBytes else { return [[key: data]] }
        return try chunks(of: data).map { try payload(.chunk($0)) }
    }

    static func chunks(of data: Data, transferID: UUID = UUID()) -> [SyncChunk] {
        let total = (data.count + chunkDataBytes - 1) / chunkDataBytes
        return (0..<total).map { index in
            let start = data.startIndex + index * chunkDataBytes
            let end = min(start + chunkDataBytes, data.endIndex)
            return SyncChunk(transferID: transferID, index: index, totalChunks: total, data: Data(data[start..<end]))
        }
    }
}

/// Collects chunks until a whole message has arrived. Chunks can arrive in any order.
struct ChunkAssembler {
    /// Unfinished transfers older than this are dropped; the sender starts over with a new ID.
    static let maxAge: TimeInterval = 60

    private struct Transfer {
        let totalChunks: Int
        let startedAt: Date
        var chunks: [Int: Data]
    }

    private var transfers: [UUID: Transfer] = [:]

    var hasTransfers: Bool { !transfers.isEmpty }

    /// Adds a chunk. Returns the whole message once its last missing chunk arrives.
    mutating func add(_ chunk: SyncChunk, now: Date = Date()) -> SyncMessage? {
        transfers = transfers.filter { now.timeIntervalSince($0.value.startedAt) < Self.maxAge }
        guard chunk.index >= 0, chunk.index < chunk.totalChunks else { return nil }

        var transfer = transfers[chunk.transferID]
            ?? Transfer(totalChunks: chunk.totalChunks, startedAt: now, chunks: [:])
        guard transfer.totalChunks == chunk.totalChunks else { return nil }
        transfer.chunks[chunk.index] = chunk.data
        guard transfer.chunks.count == transfer.totalChunks else {
            transfers[chunk.transferID] = transfer
            return nil
        }

        transfers.removeValue(forKey: chunk.transferID)
        var data = Data()
        for index in 0..<transfer.totalChunks {
            data.append(transfer.chunks[index]!)
        }
        do {
            return try SyncCodec.decode(data)
        } catch {
            Log.sync.error("Could not decode chunked message: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
