import Foundation

/// Phone: stores the watch's stream records in order and turns swings into guesses.
/// It only stores records that continue what it holds with no gap, and writes them before
/// replying, so its `have` is always true.
@MainActor
final class StreamReceiver {
    /// A swing's location is the watch GPS fix nearest in time, if one is this close.
    nonisolated static let swingFixWindow: TimeInterval = 5

    private let rounds: RoundStore
    private let streams: StreamStore
    private let guesses: GuessStore

    // Swings still waiting for the fixes around them
    private var pendingSwings: [UUID: [Swing]] = [:]

    init(rounds: RoundStore, streams: StreamStore, guesses: GuessStore) {
        self.rounds = rounds
        self.streams = streams
        self.guesses = guesses
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

        let swings = StreamRecord.records(in: fresh).compactMap { record -> Swing? in
            if case .swing(let swing) = record { return swing }
            return nil
        }
        pendingSwings[round.id, default: []] += swings
        processSwings(round.id)

        return StreamAck(roundID: round.id, have: self.have(for: round.id))
    }

    /// Makes guesses for swings whose nearby fixes have all arrived. Once the round has
    /// ended, every swing in the stream is checked, including any from before a relaunch.
    func processSwings(_ roundID: UUID) {
        guard let round = rounds.round(roundID) else { return }
        let ended = round.status == .ended
        let candidates = ended ? streams.swings(for: roundID, until: round.endedAt) : (pendingSwings[roundID] ?? [])
        guard !candidates.isEmpty else { return }

        let points = streams.points(for: roundID, until: round.endedAt)
        var waiting: [Swing] = []
        for swing in candidates {
            // Fixes arrive in order, so a later fix means no nearer one can still come
            let settled = ended || points.last.map { $0.timestamp.timeIntervalSince(swing.timestamp) >= Self.swingFixWindow } ?? false
            guard settled else {
                waiting.append(swing)
                continue
            }
            guard let fix = Self.nearestFix(to: swing.timestamp, in: points) else { continue }
            let guess = MissedMarkGuess(id: MissedMarkGuess.id(forSwingAt: swing.timestamp, roundID: roundID),
                                        coordinate: .init(latitude: fix.latitude, longitude: fix.longitude),
                                        timestamp: swing.timestamp, roundID: roundID)
            guesses.add(guess, in: round)
        }
        pendingSwings[roundID] = ended ? nil : waiting
    }

    /// The fix nearest in time to `date`, within `swingFixWindow`.
    nonisolated static func nearestFix(to date: Date, in points: [TrackPoint]) -> TrackPoint? {
        let nearest = points.min { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) }
        guard let nearest, abs(nearest.timestamp.timeIntervalSince(date)) <= swingFixWindow else { return nil }
        return nearest
    }
}
