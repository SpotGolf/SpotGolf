import Foundation
import os

/// Watch: sends each round's stream to the phone. One batch is in flight at a time, and the
/// next batch starts where the phone's last reply said it is, so a lost batch or reply is
/// simply sent again and a gap is fixed in one round trip.
@MainActor
final class StreamSender {
    /// About 1,600 records.
    static let maxBatchBytes = 40_000
    static let retryInterval: TimeInterval = 10

    /// The shortest time between two batches. Fixes that arrive sooner wait and go in the
    /// next batch, which keeps the number of messages, and battery use, down. Tests use zero.
    var minBatchInterval: TimeInterval = 0

    private let sync: SyncService
    private let rounds: RoundStore
    private let streams: StreamStore

    /// The phone's `have` for each round, from its last reply. Missing means unknown.
    private(set) var cursors: [UUID: Int] = [:]
    private(set) var isInFlight = false
    private var retryTimer: Timer?
    private var lastSendAt: Date?

    /// Called after an ended round's stream is deleted because the phone has all of it.
    var onStreamDeleted: (() -> Void)?
    private var delayedPump: Timer?

    init(sync: SyncService, rounds: RoundStore, streams: StreamStore) {
        self.sync = sync
        self.rounds = rounds
        self.streams = streams
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
            // SyncService logs the failure. The cursor has not moved, so the same records go again on the next try
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

    /// The phone's `have`, from a reply or sent on its own when the phone launches.
    func handle(_ ack: StreamAck) {
        guard let have = ack.have else {
            // The phone does not know the round
            Log.sync.error("Phone does not know round \(ack.roundID, privacy: .public); deleting its stream")
            cursors.removeValue(forKey: ack.roundID)
            streams.delete(ack.roundID)
            pump()
            return
        }
        let previous = cursors[ack.roundID]
        cursors[ack.roundID] = have
        deleteIfComplete(ack.roundID)
        // A reply that changes nothing waits for the retry timer, so the two apps can never
        // bounce the same batch back and forth
        guard have != previous else { return }
        pump()
    }

    /// Deletes an ended round's stream once the phone holds everything up to its last record.
    func deleteIfComplete(_ roundID: UUID) {
        guard let round = rounds.round(roundID), round.status == .ended,
              let have = cursors[roundID], have >= end(of: round) else { return }
        cursors.removeValue(forKey: roundID)
        streams.delete(roundID)
        onStreamDeleted?()
    }

    /// Rounds are sent oldest first. A round with an unknown cursor gets an empty batch,
    /// which the phone answers with its `have`.
    private func nextBatch() -> StreamBatch? {
        let pending = streams.roundIDs().compactMap { id -> Round? in
            if let round = rounds.round(id) { return round }
            // A stream with no round has no base to send from
            Log.sync.error("Stream for unknown round \(id, privacy: .public); deleting it")
            streams.delete(id)
            return nil
        }
        for round in pending.sorted(by: { $0.date < $1.date }) {
            let end = end(of: round)
            guard let cursor = cursors[round.id] else {
                return StreamBatch(roundID: round.id, from: end, records: Data())
            }
            guard cursor < end else { continue }
            let from = max(cursor, round.streamBase)
            let data = streams.data(for: round.id, from: from - round.streamBase, maxBytes: Self.maxBatchBytes)
            guard !data.isEmpty else { continue }
            return StreamBatch(roundID: round.id, from: from, records: data)
        }
        return nil
    }
}
