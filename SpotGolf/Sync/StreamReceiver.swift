import Foundation
import os

/// Phone: stores the watch's stream records in order. It only stores what continues what it
/// holds with no gap, and writes it before replying, so its `have` is always true.
@MainActor
final class StreamReceiver {
    private let rounds: RoundStore
    private let streams: StreamStore

    init(rounds: RoundStore, streams: StreamStore) {
        self.rounds = rounds
        self.streams = streams
    }

    /// The phone's `have` for a round: it holds records `0..<have`.
    func have(for roundID: UUID) -> Int {
        streams.count(for: roundID)
    }

    func ack(for roundID: UUID) -> StreamAck {
        StreamAck(roundID: roundID, have: have(for: roundID))
    }

    /// Applies the rules for one batch and returns the reply.
    func receive(_ batch: StreamBatch) -> StreamAck {
        guard let round = rounds.round(batch.roundID) else {
            Log.sync.error("Stream batch for unknown round \(batch.roundID)")
            return StreamAck(roundID: batch.roundID, have: nil)
        }
        receiveRecords(batch, round: round)
        return ack(for: round.id)
    }

    private func receiveRecords(_ batch: StreamBatch, round: Round) {
        let have = have(for: round.id)
        let count = batch.records.count / StreamRecord.size
        guard count > 0 else { return }
        // A gap before the batch: discard it; the reply tells the watch where to start
        guard batch.from <= have, batch.from + count > have else {
            if batch.from > have {
                Log.sync.notice("Stream gap for round \(round.id): batch from \(batch.from), have \(have)")
            }
            return
        }

        // An overlap is a resend: skip what is already stored
        let skip = (have - batch.from) * StreamRecord.size
        let fresh = batch.records.subdata(in: (batch.records.startIndex + skip)..<(batch.records.startIndex + count * StreamRecord.size))
        streams.appendData(fresh, roundID: round.id)
    }
}
