import Foundation
import os

/// Stores each round's stream from the watch: GPS fixes and swings as fixed-size records,
/// one append-only file per round. The watch records into it; the phone stores the same
/// records as they arrive, so its record count is exactly what it holds on disk.
@MainActor
final class StreamStore: ObservableObject {
    nonisolated static let fileExtension = "stream"

    private let directory: URL

    // Record counts, read from disk once per round
    private var counts: [UUID: Int] = [:]

    // Records read by `records(for:)`, kept up to date on append. The phone reads the whole
    // stream after every batch, so this saves reading and decoding the file each time.
    private var cache: [UUID: [StreamRecord]] = [:]

    /// Bumped whenever records are added or removed, so views can reload.
    @Published private(set) var revision = 0

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.directory = docs.appendingPathComponent("streams")
        }
    }

    func fileURL(for roundID: UUID) -> URL {
        directory.appendingPathComponent("\(roundID.uuidString)_watch.\(Self.fileExtension)")
    }

    func hasStream(for roundID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: roundID).path)
    }

    /// Rounds that have a stream file.
    func roundIDs() -> [UUID] {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch CocoaError.fileReadNoSuchFile {
            urls = []
        } catch {
            Log.storage.error("Could not list streams: \(String(describing: error), privacy: .public)")
            urls = []
        }
        return urls.compactMap { url in
            guard url.pathExtension == Self.fileExtension else { return nil }
            return UUID(uuidString: String(url.deletingPathExtension().lastPathComponent.prefix(36)))
        }
    }

    /// The number of whole records stored for the round.
    func count(for roundID: UUID) -> Int {
        if let count = counts[roundID] { return count }
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL(for: roundID).path)[.size] as? Int) ?? 0
        let count = size / StreamRecord.size
        counts[roundID] = count
        return count
    }

    // MARK: - Writing

    func append(_ records: [StreamRecord], roundID: UUID) {
        appendData(StreamRecord.data(for: records), roundID: roundID)
    }

    /// Appends records that are already encoded. The data is written before this returns.
    func appendData(_ data: Data, roundID: UUID) {
        let whole = data.prefix(data.count - data.count % StreamRecord.size)
        guard !whole.isEmpty else { return }
        let url = fileURL(for: roundID)
        let count = count(for: roundID)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                // Drop a partial record left by a write that was cut short, so records stay aligned
                try handle.truncate(atOffset: UInt64(count * StreamRecord.size))
                try handle.seekToEnd()
                try handle.write(contentsOf: whole)
            } else {
                try Data(whole).write(to: url)
            }
            counts[roundID] = count + whole.count / StreamRecord.size
            cache[roundID]? += StreamRecord.records(in: Data(whole))
            revision += 1
        } catch {
            Log.storage.error("Could not save stream for round \(roundID, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Keeps only the first `count` records.
    func truncate(_ roundID: UUID, to count: Int) {
        guard count < self.count(for: roundID) else { return }
        do {
            let handle = try FileHandle(forWritingTo: fileURL(for: roundID))
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(max(count, 0) * StreamRecord.size))
            counts[roundID] = max(count, 0)
            cache.removeValue(forKey: roundID)
            revision += 1
        } catch {
            Log.storage.error("Could not truncate stream for round \(roundID, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Drops every record from the first one after `date`. Returns the new count.
    @discardableResult
    func truncate(_ roundID: UUID, after date: Date) -> Int {
        let records = readRecords(for: roundID)
        if let first = records.firstIndex(where: { $0.timestamp > date }) {
            truncate(roundID, to: first)
            return first
        }
        return records.count
    }

    func delete(_ roundID: UUID) {
        do {
            try FileManager.default.removeItem(at: fileURL(for: roundID))
            Log.storage.notice("Deleted stream for round \(roundID, privacy: .public)")
        } catch CocoaError.fileNoSuchFile {
        } catch {
            Log.storage.error("Could not delete stream for round \(roundID, privacy: .public): \(String(describing: error), privacy: .public)")
        }
        counts.removeValue(forKey: roundID)
        cache.removeValue(forKey: roundID)
        revision += 1
    }

    // MARK: - Reading

    /// Encoded records starting at position `start`, at most `maxBytes` of them.
    func data(for roundID: UUID, from start: Int, maxBytes: Int) -> Data {
        let count = count(for: roundID)
        guard start < count else { return Data() }
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: fileURL(for: roundID))
        } catch {
            Log.storage.error("Could not open stream for round \(roundID, privacy: .public): \(String(describing: error), privacy: .public)")
            return Data()
        }
        defer { try? handle.close() }
        let maxRecords = max(maxBytes / StreamRecord.size, 1)
        let end = min(count, start + maxRecords)
        do {
            try handle.seek(toOffset: UInt64(start * StreamRecord.size))
            return try handle.read(upToCount: (end - start) * StreamRecord.size) ?? Data()
        } catch {
            Log.storage.error("Could not read stream for round \(roundID, privacy: .public): \(String(describing: error), privacy: .public)")
            return Data()
        }
    }

    func records(for roundID: UUID) -> [StreamRecord] {
        if let cached = cache[roundID] { return cached }
        let records = readRecords(for: roundID)
        cache[roundID] = records
        return records
    }

    private func readRecords(for roundID: UUID) -> [StreamRecord] {
        do {
            return StreamRecord.records(in: try Data(contentsOf: fileURL(for: roundID)))
        } catch CocoaError.fileReadNoSuchFile {
            return []
        } catch {
            Log.storage.error("Could not read stream for round \(roundID, privacy: .public): \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// GPS fixes up to `endedAt`, when given.
    func points(for roundID: UUID, until endedAt: Date? = nil) -> [TrackPoint] {
        records(for: roundID).compactMap { record in
            guard case .fix(let point) = record, endedAt.map({ point.timestamp <= $0 }) ?? true else { return nil }
            return point
        }
    }

    /// Swings up to `endedAt`, when given.
    func swings(for roundID: UUID, until endedAt: Date? = nil) -> [StrokeSuggestion] {
        records(for: roundID).compactMap { record in
            guard case .swing(let swing) = record, endedAt.map({ swing.timestamp <= $0 }) ?? true else { return nil }
            return swing
        }
    }

    /// Contacts up to `endedAt`, when given.
    func contacts(for roundID: UUID, until endedAt: Date? = nil) -> [ContactEvent] {
        records(for: roundID).compactMap { record in
            guard case .contact(let contact) = record, endedAt.map({ contact.timestamp <= $0 }) ?? true else { return nil }
            return contact
        }
    }
}
