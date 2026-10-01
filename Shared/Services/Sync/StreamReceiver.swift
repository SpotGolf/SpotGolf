import Foundation

/// Phone: stores the watch's stream records in order. It only stores records that continue
/// what it holds with no gap, and writes them before replying, so its `have` is always true.
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

    /// Applies the rules for one batch and returns the reply.
    func receive(_ batch: StreamBatch) -> StreamAck {
        guard let round = rounds.round(batch.roundID) else {
            return StreamAck(roundID: batch.roundID, have: nil)
        }
        let have = have(for: round.id)
        let count = batch.records.count / StreamRecord.size
        // A gap before the batch: discard it; the reply tells the watch where to start
        guard batch.from <= have, batch.from + count > have else {
            return StreamAck(roundID: round.id, have: have)
        }

        // An overlap is a resend: skip what is already stored
        let skip = (have - batch.from) * StreamRecord.size
        let fresh = batch.records.subdata(in: (batch.records.startIndex + skip)..<(batch.records.startIndex + count * StreamRecord.size))
        streams.appendData(fresh, roundID: round.id)

        return StreamAck(roundID: round.id, have: self.have(for: round.id))
    }
}
