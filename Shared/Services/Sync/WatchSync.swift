import Foundation
import os
import CoreLocation

/// The watch's side of the messaging: taking rounds the phone starts, recording the stream
/// and sending it, ending rounds, and keeping the timeline and strokes in step.
@MainActor
final class WatchSync: ObservableObject {
    let sync: SyncService
    let rounds: RoundStore
    let streams: StreamStore
    let sender: StreamSender
    let snapshots: SnapshotSync

    /// Permissions the watch needs and does not have. A new round is refused until there are none.
    var missingPermissions: () -> [AppPermission] = { [] }

    init(sync: SyncService, rounds: RoundStore, streams: StreamStore) {
        self.sync = sync
        self.rounds = rounds
        self.streams = streams
        sender = StreamSender(sync: sync, rounds: rounds, streams: streams)
        snapshots = SnapshotSync(sync: sync, rounds: rounds, sendsStrokes: false)

        sync.handler = { [weak self] message in self?.handle(message) }
        rounds.onTimelineChanged = { [weak self] round in self?.snapshots.sendTimeline(round) }
        sync.onReachabilityChange { [weak self] in self?.reachabilityChanged() }
        sender.onStreamDeleted = { [weak self] in self?.pruneFinishedRounds() }
        pruneFinishedRounds()
    }

    // MARK: - Recording

    /// Stores GPS fixes for the active round and sends them.
    func record(_ locations: [CLLocation]) {
        guard let round = rounds.activeRound else {
            Log.location.error("Dropped \(locations.count, privacy: .public) fixes: no active round")
            return
        }
        streams.append(locations.map { .fix(TrackPoint(location: $0)) }, roundID: round.id)
        sender.pump()
    }

    func record(_ swing: StrokeSuggestion) {
        guard let round = rounds.activeRound else {
            Log.swings.error("Dropped a swing: no active round")
            return
        }
        streams.append([.swing(swing)], roundID: round.id)
        sender.pump()
    }

    // MARK: - End

    /// The user ended the round on the watch. The watch is done right away; the phone is told
    /// the last record so it knows when the stream is complete.
    func endRound() {
        guard let round = rounds.activeRound else { return }
        Log.rounds.notice("Round \(round.id, privacy: .public) ended on the watch")
        end(round.id, at: Date())
        sendEndRound(round.id)
        if let end = endRoundMessage(round.id) {
            sync.queue(.endRound(end))
        }
    }

    private func end(_ roundID: UUID, at date: Date) {
        guard let round = rounds.round(roundID) else { return }
        let lastSeq = sender.end(of: round) - 1
        rounds.update(roundID) { round in
            round.lastSeq = lastSeq >= 0 ? lastSeq : nil
            round.end(at: date)
        }
        sender.deleteIfComplete(roundID)
    }

    private func endRoundMessage(_ roundID: UUID) -> EndRound? {
        guard let round = rounds.round(roundID), round.status == .ended, let endedAt = round.endedAt else { return nil }
        return EndRound(roundID: roundID, endedAt: endedAt, lastSeq: round.lastSeq)
    }

    private func sendEndRound(_ roundID: UUID) {
        guard let end = endRoundMessage(roundID), rounds.round(roundID)?.endConfirmed == false else { return }
        sync.send(.endRound(end), reply: { [weak self] reply in
            if case .endAck(let ack) = reply {
                self?.rounds.update(ack.roundID) { $0.endConfirmed = true }
                self?.pruneFinishedRounds()
            }
        })
    }

    // MARK: - Receive

    private func handle(_ message: SyncMessage) -> SyncMessage? {
        switch message {
        case .startRound(let start):
            return startRound(start)
        case .cancelRound(let cancel):
            Log.rounds.notice("Round \(cancel.roundID, privacy: .public) cancelled by the phone")
            rounds.deleteRound(cancel.roundID)
            streams.delete(cancel.roundID)
            return nil
        case .endRequest(let request):
            return .endAck(endRequested(request))
        case .endAck(let ack):
            rounds.update(ack.roundID) { $0.endConfirmed = true }
            pruneFinishedRounds()
            return nil
        case .streamAck(let ack):
            sender.handle(ack)
            return nil
        case .holeTimeline(let timeline):
            snapshots.apply(timeline)
            return nil
        case .strokes(let strokes):
            snapshots.apply(strokes)
            return nil
        case .context(let context):
            snapshots.apply(context)
            return nil
        case .startRoundAck, .startRoundRefused, .endRound, .streamBatch, .chunk:
            return nil
        }
    }

    /// Takes the round the phone started, or refuses it while permissions are missing. A
    /// repeat of the same start for a round already recording just confirms again.
    private func startRound(_ start: StartRound) -> SyncMessage? {
        if rounds.round(start.roundID)?.isActive != true {
            let missing = missingPermissions()
            guard missing.isEmpty else {
                Log.rounds.error("Round \(start.roundID, privacy: .public) refused: missing \(missing.map(\.rawValue).joined(separator: ", "), privacy: .public)")
                return .startRoundRefused(StartRoundRefused(roundID: start.roundID, missing: missing))
            }
        }

        let selection: CourseSelection
        do {
            selection = try JSONDecoder().decode(CourseSelection.self, from: start.course.gzipDecompressed())
        } catch {
            Log.sync.error("Could not decode the course for round \(start.roundID, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }

        Log.rounds.notice("Round \(start.roundID, privacy: .public) started by the phone")

        // Another round still recording ends the usual way first
        if let other = rounds.activeRound, other.id != start.roundID {
            end(other.id, at: Date())
            sendEndRound(other.id)
            if let end = endRoundMessage(other.id) {
                sync.queue(.endRound(end))
            }
        }

        if rounds.round(start.roundID) == nil {
            rounds.startRound(id: start.roundID, date: start.date, courseSelection: selection)
            rounds.update(start.roundID) { round in
                round.holeTimeline = HoleTimeline.normalized(start.holeTimeline)
                round.ensureHole(round.currentHoleIndex)
            }
        } else {
            rounds.update(start.roundID) { round in
                round.status = .active
                round.endedAt = nil
                round.lastSeq = nil
                round.endConfirmed = false
                round.mergeTimeline(start.holeTimeline)
            }
        }
        // A stream still on the watch keeps its own base; the phone holds only part of it
        if !streams.hasStream(for: start.roundID) {
            rounds.update(start.roundID) { $0.streamBase = start.streamBase }
        }
        rounds.applyStrokes(start.strokes)
        sender.pump()
        return .startRoundAck(StartRoundAck(roundID: start.roundID))
    }

    /// The phone ended the round. Records after its end time are dropped, and the reply
    /// gives the last record so the phone knows when it has everything.
    private func endRequested(_ request: EndRequest) -> EndAck {
        guard let round = rounds.round(request.roundID) else {
            Log.rounds.notice("End request for unknown round \(request.roundID, privacy: .public)")
            return EndAck(roundID: request.roundID, lastSeq: nil)
        }
        if round.isActive {
            Log.rounds.notice("Round \(round.id, privacy: .public) ended by the phone")
            streams.truncate(round.id, after: request.endedAt)
            end(round.id, at: request.endedAt)
            // The request may have come through the queue, which has no reply. The queued
            // copy of the end tells the phone the last record either way.
            if let end = endRoundMessage(round.id) {
                sync.queue(.endRound(end))
            }
        }
        rounds.update(round.id) { $0.endConfirmed = true }
        let lastSeq = rounds.round(round.id)?.lastSeq
        pruneFinishedRounds()
        return EndAck(roundID: round.id, lastSeq: lastSeq)
    }

    /// Rounds the phone has fully are kept this long, so late repeats of the end still get
    /// the real last record.
    static let finishedRoundKeepTime: TimeInterval = 24 * 60 * 60

    /// Deletes rounds the phone has fully: ended a day ago, end confirmed, and stream sent
    /// and deleted. Each round holds its whole course, and every save rewrites all rounds,
    /// so the list must not grow round after round. A resume on the phone sends the round again.
    func pruneFinishedRounds(now: Date = Date()) {
        for round in rounds.rounds where round.status == .ended && round.endConfirmed
            && (round.endedAt.map { now.timeIntervalSince($0) > Self.finishedRoundKeepTime } ?? true)
            && !streams.hasStream(for: round.id) {
            rounds.deleteRound(round.id)
        }
    }

    // MARK: - Reachability

    private func reachabilityChanged() {
        guard sync.transport.isReachable else { return }
        for round in rounds.rounds where round.status == .ended && !round.endConfirmed {
            sendEndRound(round.id)
        }
        sender.pump()
    }
}
