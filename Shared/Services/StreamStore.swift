import Foundation
import SwiftData
import Observation
import os

/// Stores each round's stream from the watch with SwiftData: GPS fixes, swings and contacts as
/// fixed-size records, one `StreamEntry` per record. The watch records into it; the phone stores
/// the same records as they arrive, so its record count is exactly what it holds.
@MainActor
@Observable
final class StreamStore {
    @ObservationIgnored private let context: ModelContext

    // Record counts per round with a stream, read once at launch and kept up to date
    @ObservationIgnored private var counts: [UUID: Int] = [:]

    // Records read by `records(for:)`, kept up to date on append. The phone reads the whole
    // stream after every batch, so this saves fetching and decoding it each time.
    @ObservationIgnored private var cache: [UUID: [StreamRecord]] = [:]

    /// Bumped whenever records are added or removed, so views can reload.
    private(set) var revision = 0

    init(context: ModelContext) {
        self.context = context
        var roundIDsOnly = FetchDescriptor<StreamEntry>()
        roundIDsOnly.propertiesToFetch = [\.roundID]
        do {
            for entry in try context.fetch(roundIDsOnly) {
                counts[entry.roundID, default: 0] += 1
            }
        } catch {
            Log.storage.error("Could not load streams: \(String(describing: error))")
        }
    }

    func hasStream(for roundID: UUID) -> Bool {
        count(for: roundID) > 0
    }

    /// Rounds that have records.
    func roundIDs() -> [UUID] {
        counts.filter { $0.value > 0 }.map(\.key)
    }

    /// The number of records stored for the round.
    func count(for roundID: UUID) -> Int {
        counts[roundID] ?? 0
    }

    // MARK: - Writing

    func append(_ records: [StreamRecord], roundID: UUID) {
        appendData(StreamRecord.data(for: records), roundID: roundID)
    }

    /// Appends records that are already encoded. A partial record at the end is dropped. The
    /// records are saved before this returns.
    func appendData(_ data: Data, roundID: UUID) {
        let start = count(for: roundID)
        var added: [StreamRecord] = []
        var offset = data.startIndex
        while data.endIndex - offset >= StreamRecord.size {
            let bytes = Data(data[offset..<offset + StreamRecord.size])
            context.insert(StreamEntry(roundID: roundID, index: start + added.count, record: bytes))
            if let record = StreamRecord(record: bytes) {
                added.append(record)
            }
            offset += StreamRecord.size
        }
        let addedCount = (offset - data.startIndex) / StreamRecord.size
        guard addedCount > 0, save("save stream for round \(roundID)") else { return }
        counts[roundID] = start + addedCount
        cache[roundID]? += added
        revision += 1
    }

    /// Keeps only the first `count` records.
    func truncate(_ roundID: UUID, to count: Int) {
        let kept = max(count, 0)
        guard kept < self.count(for: roundID) else { return }
        do {
            try context.delete(model: StreamEntry.self, where: #Predicate { $0.roundID == roundID && $0.index >= kept })
        } catch {
            Log.storage.error("Could not truncate stream for round \(roundID): \(String(describing: error))")
            return
        }
        guard save("truncate stream for round \(roundID)") else { return }
        counts[roundID] = kept
        cache.removeValue(forKey: roundID)
        revision += 1
    }

    /// Drops every record from the first one after `date`. Returns the new count.
    @discardableResult
    func truncate(_ roundID: UUID, after date: Date) -> Int {
        let records = records(for: roundID)
        if let first = records.firstIndex(where: { $0.timestamp > date }) {
            truncate(roundID, to: first)
            return first
        }
        return records.count
    }

    func delete(_ roundID: UUID) {
        do {
            try context.delete(model: StreamEntry.self, where: #Predicate { $0.roundID == roundID })
        } catch {
            Log.storage.error("Could not delete stream for round \(roundID): \(String(describing: error))")
            return
        }
        guard save("delete stream for round \(roundID)") else { return }
        Log.storage.notice("Deleted stream for round \(roundID)")
        counts.removeValue(forKey: roundID)
        cache.removeValue(forKey: roundID)
        revision += 1
    }

    private func save(_ action: String) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            Log.storage.error("Could not \(action): \(String(describing: error))")
            context.rollback()
            return false
        }
    }

    // MARK: - Reading

    /// Encoded records starting at position `start`, at most `maxBytes` of them.
    func data(for roundID: UUID, from start: Int, maxBytes: Int) -> Data {
        let count = count(for: roundID)
        guard start < count else { return Data() }
        let end = min(count, start + max(maxBytes / StreamRecord.size, 1))
        return entries(for: roundID, from: start, to: end).reduce(into: Data()) { $0.append($1.record) }
    }

    func records(for roundID: UUID) -> [StreamRecord] {
        if let cached = cache[roundID] { return cached }
        let records = entries(for: roundID, from: 0, to: count(for: roundID)).compactMap { StreamRecord(record: $0.record) }
        cache[roundID] = records
        return records
    }

    /// The entries with an index from `start` up to `end`, in order.
    private func entries(for roundID: UUID, from start: Int, to end: Int) -> [StreamEntry] {
        guard start < end else { return [] }
        let range = FetchDescriptor<StreamEntry>(
            predicate: #Predicate { $0.roundID == roundID && $0.index >= start && $0.index < end },
            sortBy: [SortDescriptor(\.index)])
        do {
            return try context.fetch(range)
        } catch {
            Log.storage.error("Could not read stream for round \(roundID): \(String(describing: error))")
            return []
        }
    }

    /// GPS fixes up to `endedAt`, when given.
    func points(for roundID: UUID, until endedAt: Date? = nil) -> [TrackPoint] {
        records(for: roundID, until: endedAt) { record in
            if case .fix(let point) = record { return point }
            return nil
        }
    }

    /// Swings up to `endedAt`, when given.
    func swings(for roundID: UUID, until endedAt: Date? = nil) -> [StrokeSuggestion] {
        records(for: roundID, until: endedAt) { record in
            if case .swing(let swing) = record { return swing }
            return nil
        }
    }

    /// Contacts up to `endedAt`, when given.
    func contacts(for roundID: UUID, until endedAt: Date? = nil) -> [ContactEvent] {
        records(for: roundID, until: endedAt) { record in
            if case .contact(let contact) = record { return contact }
            return nil
        }
    }

    /// The watch's workout and sensor events up to `endedAt`, when given.
    func events(for roundID: UUID, until endedAt: Date? = nil) -> [StreamEvent] {
        records(for: roundID, until: endedAt) { record in
            if case .event(let event) = record { return event }
            return nil
        }
    }

    /// The records of one kind up to `endedAt`, when given.
    private func records<T>(for roundID: UUID, until endedAt: Date?, _ pick: (StreamRecord) -> T?) -> [T] {
        records(for: roundID).compactMap { record in
            guard endedAt.map({ record.timestamp <= $0 }) ?? true else { return nil }
            return pick(record)
        }
    }
}
