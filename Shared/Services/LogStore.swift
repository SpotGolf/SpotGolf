import Foundation
import Observation
import os
import SwiftData

/// Saves the app's log lines with SwiftData, one `LogEntry` each, and reads them back for
/// the sync, the log screen and the export. The store is `Log`'s sink: lines arrive from any
/// thread, are given the round in progress at once, and are saved once a second, or at once
/// by `flush()` before a stream batch is built. See plans/2026-10-10-app-log.md.
@MainActor
@Observable
final class LogStore {
    /// Lines outside any round are kept to this many.
    static let outsideRoundLimit = 2_000
    static let flushInterval: TimeInterval = 1
    /// Lines from this long before a round starts are moved into it.
    static let preRoundAge: TimeInterval = 5 * 60

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let outsideLimit: Int
    /// The store's own failures go to the unified log only, so a broken store does not log
    /// about itself into itself once a second.
    @ObservationIgnored private let logger = Logger(subsystem: Log.subsystem, category: "storage")

    /// The round a new line belongs to: the round in progress, if any. The app sets it.
    @ObservationIgnored var roundIDForNewLines: () -> UUID? = { nil }
    /// Called after new lines are saved, so the watch can send them.
    @ObservationIgnored var onFlush: (() -> Void)?

    @ObservationIgnored private var pending: [(roundID: UUID?, line: LogLine)] = []
    @ObservationIgnored private var flushTimer: Timer?
    @ObservationIgnored private var counts: [LineKey: Int] = [:]
    @ObservationIgnored private var nextSeqs: [LineKey: Int] = [:]

    /// Bumped whenever lines are added, moved or removed, so views can reload.
    private(set) var revision = 0

    private struct LineKey: Hashable {
        let roundID: UUID?
        let device: LogDevice
    }

    init(context: ModelContext, outsideLimit: Int = LogStore.outsideRoundLimit) {
        self.context = context
        self.outsideLimit = outsideLimit
    }

    // MARK: - Sink

    /// `Log`'s sink. Any thread.
    nonisolated func receive(_ line: LogLine) {
        Task { @MainActor in self.enqueue(line) }
    }

    /// Gives the line its round now and saves it with the next flush.
    func enqueue(_ line: LogLine) {
        pending.append((roundIDForNewLines(), line))
        guard flushTimer == nil else { return }
        flushTimer = Timer.scheduledTimer(withTimeInterval: Self.flushInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
    }

    /// Saves every line waiting. Lines are grouped by round, in the order they were written.
    func flush() {
        flushTimer?.invalidate()
        flushTimer = nil
        guard !pending.isEmpty else { return }
        let lines = pending
        pending = []
        var groups: [(roundID: UUID?, lines: [LogLine])] = []
        for (roundID, line) in lines {
            if let last = groups.indices.last, groups[last].roundID == roundID {
                groups[last].lines.append(line)
            } else {
                groups.append((roundID, [line]))
            }
        }
        for group in groups {
            append(group.lines, roundID: group.roundID)
        }
        onFlush?()
    }

    // MARK: - Writing

    /// Appends lines to a round, or outside any round with nil, numbering them after the
    /// round's last line from the same device. Saved before this returns.
    func append(_ lines: [LogLine], roundID: UUID?) {
        guard !lines.isEmpty else { return }
        // Read before inserting: a fetch sees the inserted entries before they are saved
        var bases: [LineKey: (count: Int, next: Int)] = [:]
        var added: [LineKey: Int] = [:]
        for line in lines {
            let key = LineKey(roundID: roundID, device: line.device)
            let base = bases[key] ?? (count(for: key), nextSeq(for: key))
            bases[key] = base
            let seq = base.next + (added[key] ?? 0)
            context.insert(LogEntry(roundID: roundID, device: line.device, seq: seq, line: line))
            added[key, default: 0] += 1
        }
        guard save("save log lines") else { return }
        for (key, count) in added {
            counts[key] = bases[key]!.count + count
            nextSeqs[key] = bases[key]!.next + count
        }
        if roundID == nil {
            trimOutsideRound()
        }
        revision += 1
    }

    /// Keeps only the newest `outsideLimit` lines outside any round.
    private func trimOutsideRound() {
        let outside = LogDevice.allCases.reduce(0) { $0 + count(for: LineKey(roundID: nil, device: $1)) }
        let excess = outside - outsideLimit
        guard excess > 0 else { return }
        var oldest = FetchDescriptor<LogEntry>(predicate: #Predicate { $0.roundID == nil },
                                               sortBy: [SortDescriptor(\.timestamp), SortDescriptor(\.seq)])
        oldest.fetchLimit = excess
        do {
            let entries = try context.fetch(oldest)
            for entry in entries {
                let key = LineKey(roundID: nil, device: LogDevice(rawValue: entry.device) ?? .phone)
                counts[key] = count(for: key) - 1
                context.delete(entry)
            }
        } catch {
            logger.error("Could not read the oldest log lines: \(String(describing: error), privacy: .public)")
            return
        }
        _ = save("trim log lines")
    }

    /// Moves `device`'s lines from the last `age` into the round, after its last line, so
    /// what came just before the round is read with it.
    func moveRecentLines(into roundID: UUID, device: LogDevice = Log.device,
                         age: TimeInterval = LogStore.preRoundAge, now: Date = Date()) {
        let deviceName = device.rawValue
        let since = now.addingTimeInterval(-age)
        let recent = FetchDescriptor<LogEntry>(
            predicate: #Predicate { $0.roundID == nil && $0.device == deviceName && $0.timestamp >= since },
            sortBy: [SortDescriptor(\.seq)])
        let entries: [LogEntry]
        do {
            entries = try context.fetch(recent)
        } catch {
            logger.error("Could not read the recent log lines: \(String(describing: error), privacy: .public)")
            return
        }
        guard !entries.isEmpty else { return }
        let key = LineKey(roundID: roundID, device: device)
        let outsideKey = LineKey(roundID: nil, device: device)
        // Read before changing anything: a fetch sees the changes before they are saved
        let roundCount = count(for: key)
        let outsideCount = count(for: outsideKey)
        var seq = nextSeq(for: key)
        for entry in entries {
            entry.roundID = roundID
            entry.seq = seq
            seq += 1
        }
        guard save("move log lines into round \(roundID)") else { return }
        counts[key] = roundCount + entries.count
        nextSeqs[key] = seq
        counts[outsideKey] = outsideCount - entries.count
        revision += 1
    }

    func delete(_ roundID: UUID) {
        let id: UUID? = roundID
        do {
            try context.delete(model: LogEntry.self, where: #Predicate { $0.roundID == id })
        } catch {
            logger.error("Could not delete the log for round \(roundID, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        guard save("delete the log for round \(roundID)") else { return }
        for device in LogDevice.allCases {
            let key = LineKey(roundID: roundID, device: device)
            counts.removeValue(forKey: key)
            nextSeqs.removeValue(forKey: key)
        }
        revision += 1
    }

    private func save(_ action: String) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            logger.error("Could not \(action, privacy: .public): \(String(describing: error), privacy: .public)")
            context.rollback()
            return false
        }
    }

    // MARK: - Reading

    /// The number of lines from `device` in the round, or outside any round with nil.
    func count(for roundID: UUID?, device: LogDevice) -> Int {
        count(for: LineKey(roundID: roundID, device: device))
    }

    func hasLines(for roundID: UUID) -> Bool {
        LogDevice.allCases.contains { count(for: roundID, device: $0) > 0 }
    }

    private func count(for key: LineKey) -> Int {
        if let cached = counts[key] { return cached }
        let id = key.roundID
        let device = key.device.rawValue
        let descriptor = FetchDescriptor<LogEntry>(predicate: #Predicate { $0.roundID == id && $0.device == device })
        let count = (try? context.fetchCount(descriptor)) ?? 0
        counts[key] = count
        return count
    }

    /// The `seq` the next line gets: one past the highest saved, which is the count unless
    /// old lines were trimmed.
    private func nextSeq(for key: LineKey) -> Int {
        if let cached = nextSeqs[key] { return cached }
        let id = key.roundID
        let device = key.device.rawValue
        var last = FetchDescriptor<LogEntry>(predicate: #Predicate { $0.roundID == id && $0.device == device },
                                             sortBy: [SortDescriptor(\.seq, order: .reverse)])
        last.fetchLimit = 1
        let next = ((try? context.fetch(last))?.first?.seq).map { $0 + 1 } ?? 0
        nextSeqs[key] = next
        return next
    }

    /// Every line in the round, or outside any round with nil, in time order.
    func lines(for roundID: UUID?) -> [LogLine] {
        let id = roundID
        let descriptor = FetchDescriptor<LogEntry>(predicate: #Predicate { $0.roundID == id },
                                                   sortBy: [SortDescriptor(\.timestamp), SortDescriptor(\.seq)])
        do {
            return try context.fetch(descriptor).map(\.line)
        } catch {
            logger.error("Could not read the log: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// The round's lines from `device` with `seq` from `start`, at most `limit` of them and
    /// about `maxBytes` of text, in order. For the watch's batches.
    func lines(for roundID: UUID, device: LogDevice, from start: Int, limit: Int, maxBytes: Int) -> [LogLine] {
        let id: UUID? = roundID
        let deviceName = device.rawValue
        var descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate { $0.roundID == id && $0.device == deviceName && $0.seq >= start },
            sortBy: [SortDescriptor(\.seq)])
        descriptor.fetchLimit = limit
        let entries: [LogEntry]
        do {
            entries = try context.fetch(descriptor)
        } catch {
            logger.error("Could not read the log for round \(roundID, privacy: .public): \(String(describing: error), privacy: .public)")
            return []
        }
        var lines: [LogLine] = []
        var bytes = 0
        for entry in entries {
            let line = entry.line
            bytes += line.message.utf8.count + line.category.utf8.count + 40
            if bytes > maxBytes, !lines.isEmpty { break }
            lines.append(line)
        }
        return lines
    }

    /// The lines as an exported file, one per line.
    static func text(_ lines: [LogLine]) -> String {
        lines.map(\.text).joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }
}
