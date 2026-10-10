import Foundation
import os

/// Phone: stores the watch's stream records and log lines in order. It only stores what
/// continues what it holds with no gap, and writes it before replying, so its `have` and
/// `haveLogs` are always true.
@MainActor
final class StreamReceiver {
    private let rounds: RoundStore
    private let streams: StreamStore
    private let logs: LogStore

    init(rounds: RoundStore, streams: StreamStore, logs: LogStore) {
        self.rounds = rounds
        self.streams = streams
        self.logs = logs
    }

    /// The phone's `have` for a round: it holds records `0..<have`.
    func have(for roundID: UUID) -> Int {
        streams.count(for: roundID)
    }

    /// The phone's `haveLogs` for a round: it holds the watch's lines `0..<haveLogs`.
    func haveLogs(for roundID: UUID) -> Int {
        logs.count(for: roundID, device: .watch)
    }

    func ack(for roundID: UUID) -> StreamAck {
        StreamAck(roundID: roundID, have: have(for: roundID), haveLogs: haveLogs(for: roundID))
    }

    /// Applies the rules for one batch and returns the reply.
    func receive(_ batch: StreamBatch) -> StreamAck {
        guard let round = rounds.round(batch.roundID) else {
            Log.sync.error("Stream batch for unknown round \(batch.roundID)")
            return StreamAck(roundID: batch.roundID, have: nil)
        }
        receiveRecords(batch, round: round)
        receiveLogs(batch, round: round)
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

    private func receiveLogs(_ batch: StreamBatch, round: Round) {
        guard let from = batch.logsFrom, let lines = batch.logs, !lines.isEmpty else { return }
        let have = haveLogs(for: round.id)
        guard from <= have, from + lines.count > have else {
            if from > have {
                Log.sync.notice("Log gap for round \(round.id): batch from \(from), have \(have)")
            }
            return
        }
        // An overlap is a resend: skip what is already stored
        logs.append(Array(lines[(have - from)...]), roundID: round.id)
    }
}
