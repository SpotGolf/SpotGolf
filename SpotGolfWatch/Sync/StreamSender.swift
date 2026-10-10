import Foundation
import os

/// Watch: sends each round's stream and log lines to the phone. One batch is in flight at a
/// time, and the next batch starts where the phone's last reply said it is, so a lost batch
/// or reply is simply sent again and a gap is fixed in one round trip. Records and lines have
/// their own cursors, since lines keep coming after the last record.
@MainActor
final class StreamSender {
    /// About 1,600 records.
    static let maxBatchBytes = 40_000
    /// Lines per batch, and about how much of their text.
    static let maxBatchLines = 200
    static let maxBatchLogBytes = 20_000
    static let retryInterval: TimeInterval = 10

    /// The shortest time between two batches. Fixes that arrive sooner wait and go in the
    /// next batch, which keeps the number of messages, and battery use, down. Tests use zero.
    var minBatchInterval: TimeInterval = 0

    private let sync: SyncService
    private let rounds: RoundStore
    private let streams: StreamStore
    private let logs: LogStore

    /// The phone's `have` for each round, from its last reply. Missing means unknown.
    private(set) var cursors: [UUID: Int] = [:]
    /// The phone's `haveLogs` for each round. Missing means unknown.
    private(set) var logCursors: [UUID: Int] = [:]
    private(set) var isInFlight = false
    private var retryTimer: Timer?
    private var lastSendAt: Date?

    /// Called after an ended round's stream is deleted because the phone has all of it.
    var onStreamDeleted: (() -> Void)?
    private var delayedPump: Timer?

    init(sync: SyncService, rounds: RoundStore, streams: StreamStore, logs: LogStore) {
        self.sync = sync
        self.rounds = rounds
        self.streams = streams
        self.logs = logs
    }

    /// Retries every `retryInterval` while there is anything to send.
    func startRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: Self.retryInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pump() }
        }
    }

    /// The index after the round's last record.
    func end(of round: Round) -> Int {
        round.streamBase + streams.count(for: round.id)
    }

    /// The `seq` after the round's last log line.
    func logEnd(of round: Round) -> Int {
        round.logBase + logs.count(for: round.id, device: .watch)
    }

    /// Sends the next batch, if there is one and nothing is in flight.
    func pump() {
        guard !isInFlight, sync.transport.isReachable else { return }
        if let lastSendAt {
            let wait = minBatchInterval - Date().timeIntervalSince(lastSendAt)
            if wait > 0 {
                pumpLater(after: wait)
                return
            }
        }
        logs.flush()
        guard let batch = nextBatch() else { return }

        isInFlight = true
        lastSendAt = Date()
        sync.send(.streamBatch(batch), reply: { [weak self] reply in
            guard let self else { return }
            isInFlight = false
            if case .streamAck(let ack) = reply {
                handle(ack)
            }
        }, failure: { [weak self] _ in
            // SyncService logs the failure. The cursors have not moved, so the same records and lines go again on the next try
            self?.isInFlight = false
        })
    }

    private func pumpLater(after wait: TimeInterval) {
        guard delayedPump == nil else { return }
        delayedPump = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.delayedPump = nil
                self?.pump()
            }
        }
    }

    /// The phone's `have` and `haveLogs`, from a reply or sent on their own when the phone launches.
    func handle(_ ack: StreamAck) {
        guard let have = ack.have else {
            // The phone does not know the round
            Log.sync.error("Phone does not know round \(ack.roundID); deleting its stream")
            cursors.removeValue(forKey: ack.roundID)
            logCursors.removeValue(forKey: ack.roundID)
            streams.delete(ack.roundID)
            logs.delete(ack.roundID)
            pump()
            return
        }
        let previous = cursors[ack.roundID]
        let previousLogs = logCursors[ack.roundID]
        cursors[ack.roundID] = have
        // A phone from before the app log says nothing about lines: it never holds them
        logCursors[ack.roundID] = ack.haveLogs ?? rounds.round(ack.roundID).map(logEnd(of:)) ?? 0
        deleteIfComplete(ack.roundID)
        // A reply that changes nothing waits for the retry timer, so the two apps can never
        // bounce the same batch back and forth
        guard have != previous || logCursors[ack.roundID] != previousLogs else { return }
        pump()
    }

    /// Deletes an ended round's stream and log once the phone holds everything up to their
    /// last record and line.
    func deleteIfComplete(_ roundID: UUID) {
        guard let round = rounds.round(roundID), round.status == .ended,
              let have = cursors[roundID], have >= end(of: round),
              let haveLogs = logCursors[roundID], haveLogs >= logEnd(of: round) else { return }
        cursors.removeValue(forKey: roundID)
        logCursors.removeValue(forKey: roundID)
        streams.delete(roundID)
        logs.delete(roundID)
        onStreamDeleted?()
    }

    /// Rounds the watch still has something of: a stream, or log lines.
    private func pendingRoundIDs() -> [UUID] {
        var ids = Set(streams.roundIDs())
        for round in rounds.rounds where logs.count(for: round.id, device: .watch) > 0 {
            ids.insert(round.id)
        }
        return Array(ids)
    }

    /// Rounds are sent oldest first. A round with an unknown cursor gets an empty batch,
    /// which the phone answers with its `have` and `haveLogs`.
    private func nextBatch() -> StreamBatch? {
        let pending = pendingRoundIDs().compactMap { id -> Round? in
            if let round = rounds.round(id) { return round }
            // A stream with no round has no base to send from
            Log.sync.error("Stream for unknown round \(id); deleting it")
            streams.delete(id)
            logs.delete(id)
            return nil
        }
        for round in pending.sorted(by: { $0.date < $1.date }) {
            let end = end(of: round)
            let logEnd = logEnd(of: round)
            guard let cursor = cursors[round.id], let logCursor = logCursors[round.id] else {
                return StreamBatch(roundID: round.id, from: end, records: Data(), logsFrom: logEnd, logs: [])
            }
            var from = cursor
            var data = Data()
            if cursor < end {
                from = max(cursor, round.streamBase)
                data = streams.data(for: round.id, from: from - round.streamBase, maxBytes: Self.maxBatchBytes)
            }
            var logsFrom = logCursor
            var lines: [LogLine] = []
            if logCursor < logEnd {
                logsFrom = max(logCursor, round.logBase)
                lines = logs.lines(for: round.id, device: .watch, from: logsFrom - round.logBase,
                                   limit: Self.maxBatchLines, maxBytes: Self.maxBatchLogBytes)
            }
            guard !data.isEmpty || !lines.isEmpty else { continue }
            return StreamBatch(roundID: round.id, from: from, records: data, logsFrom: logsFrom, logs: lines)
        }
        return nil
    }
}
