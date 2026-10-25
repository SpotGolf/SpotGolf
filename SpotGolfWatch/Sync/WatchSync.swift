import Foundation
import Observation
import os
import CoreLocation

/// The watch's side of the messaging: taking rounds the phone starts, recording the stream
/// and sending it, ending rounds, and keeping the timeline and strokes in step.
@MainActor
@Observable
final class WatchSync {
    let sync: SyncService
    let rounds: RoundStore
    let streams: StreamStore
    let logs: LogStore
    let sender: StreamSender
    let snapshots: SnapshotSync

    /// Where the pre-round checks are for a round. A new round starts only once they pass.
    /// Without checks set, as in tests of other flows, every round passes.
    @ObservationIgnored var preRoundCheck: (UUID) -> PreRoundCheckState = { _ in .passed }

    /// Starts the pre-round checks for a round. Whoever runs them calls
    /// `preRoundChecksFinished` when they end.
    @ObservationIgnored var runPreRoundChecks: (UUID) -> Void = { _ in }

    /// The latest start for each round whose checks are running, finished once they end.
    @ObservationIgnored private var checkingStarts: [UUID: StartRound] = [:]

    /// Called on the main actor with the phone's settings each time they arrive for the active
    /// round: with the start, when the round is opened on the phone, and in the context.
    @ObservationIgnored var onSettings: ((RoundSettingsMessage) -> Void)?

    /// This app's version. A round from a phone app on any other version is refused, so the two
    /// never record with different code. Tests set it.
    @ObservationIgnored var version = AppVersion.text()

    /// Events from before a round is active, kept for the round that comes: the workout the
    /// phone launches starts before the round arrives.
    @ObservationIgnored private var pendingEvents: [StreamEvent] = []
    static let pendingEventLimit = 50
    static let pendingEventAge: TimeInterval = 5 * 60

    /// Where the phone's Debug Logging setting is kept, for lines outside a round.
    static let debugLoggingKey = "debugLogging"
    /// Where the phone's Putt Lab During Rounds setting is kept, for a round resumed after a relaunch.
    static let puttLabKey = "puttLabInRounds"

    /// The last Putt Lab During Rounds setting the phone sent. On until the phone says otherwise.
    static var puttLabInRounds: Bool {
        UserDefaults.standard.object(forKey: puttLabKey) as? Bool ?? true
    }
    /// Where the phone's Green Zone setting is kept, for a round resumed after a relaunch.
    static let greenZoneKey = "greenZone"

    /// The last Green Zone setting the phone sent, in meters. The default until the phone says.
    static var greenZone: Double {
        UserDefaults.standard.object(forKey: greenZoneKey) as? Double ?? HoleShape.chipZoneMargin
    }

    init(sync: SyncService, rounds: RoundStore, streams: StreamStore, logs: LogStore) {
        self.sync = sync
        self.rounds = rounds
        self.streams = streams
        self.logs = logs
        sender = StreamSender(sync: sync, rounds: rounds, streams: streams, logs: logs)
        snapshots = SnapshotSync(sync: sync, rounds: rounds, sendsStrokes: false)

        sync.handler = { [weak self] message in self?.handle(message) }
        rounds.addListener { [weak self] event in self?.roundChanged(event) }
        sync.onReachabilityChange { [weak self] in self?.reachabilityChanged() }
        sender.onStreamDeleted = { [weak self] in self?.pruneFinishedRounds() }
        // New lines go with the next batch
        logs.onFlush = { [weak self] in self?.sender.pump() }
        pruneFinishedRounds()
    }

    /// Sends changes made on the watch to the phone. Strokes change only on the phone.
    private func roundChanged(_ event: RoundEvent) {
        switch event {
        case .displayHoleChanged(let round): snapshots.sendDisplayHole(round)
        case .pinsChanged(let round): snapshots.sendPins(round)
        case .strokesChanged, .roundsChanged: break
        }
    }

    // MARK: - Recording

    /// Stores GPS fixes for the active round and sends them.
    func record(_ locations: [CLLocation]) {
        guard let round = rounds.activeRound else {
            Log.location.error("Dropped \(locations.count) fixes: no active round")
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

    func record(_ contact: ContactEvent) {
        guard let round = rounds.activeRound else {
            Log.contacts.error("Dropped a contact: no active round")
            return
        }
        streams.append([.contact(contact)], roundID: round.id)
        sender.pump()
    }

    /// Stores a workout or sensor event for the active round, or keeps it for the next round.
    func record(_ event: StreamEvent) {
        guard let round = rounds.activeRound else {
            pendingEvents.append(event)
            if pendingEvents.count > Self.pendingEventLimit {
                pendingEvents.removeFirst(pendingEvents.count - Self.pendingEventLimit)
            }
            return
        }
        streams.append([.event(event)], roundID: round.id)
        sender.pump()
    }

    // MARK: - End

    /// The user ended the round on the watch. The watch is done right away; the phone is told
    /// the last record so it knows when the stream is complete.
    func endRound() {
        guard let round = rounds.activeRound else { return }
        Log.rounds.notice("Round \(round.id) ended on the watch")
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
            Log.rounds.notice("Round \(cancel.roundID) cancelled by the phone")
            rounds.deleteRound(cancel.roundID)
            streams.delete(cancel.roundID)
            logs.delete(cancel.roundID)
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
        case .displayHole(let displayHole):
            snapshots.apply(displayHole)
            return nil
        case .pins(let pins):
            snapshots.apply(pins)
            return nil
        case .strokes(let strokes):
            snapshots.apply(strokes)
            return nil
        case .context(let context):
            snapshots.apply(context)
            if let settings = context.settings {
                apply(settings)
            }
            return nil
        case .settings(let settings):
            apply(settings)
            return nil
        case .startRoundAck, .startRoundRefused, .startRoundChecking, .endRound, .streamBatch, .chunk:
            return nil
        }
    }

    /// Takes the round the phone started once the pre-round checks pass, or refuses it while
    /// the phone app is another version or the checks failed. While the checks run, the reply
    /// says so, and the ack or refusal follows as its own message. A failed check runs again on
    /// the next start, which is the phone's Retry. A repeat of the same start for a round
    /// already recording just confirms again.
    private func startRound(_ start: StartRound) -> SyncMessage? {
        guard start.version == version else {
            Log.rounds.error("Round \(start.roundID) refused: the phone app is version \(start.version), this watch app \(self.version)")
            return .startRoundRefused(StartRoundRefused(roundID: start.roundID, reason: .versionMismatch(watchVersion: version)))
        }
        if rounds.round(start.roundID)?.isActive != true {
            switch preRoundCheck(start.roundID) {
            case .passed:
                break
            case .running:
                checkingStarts[start.roundID] = start
                return .startRoundChecking(StartRoundChecking(roundID: start.roundID))
            case .notRun, .failed:
                Log.rounds.notice("Round \(start.roundID): running the pre-round checks")
                checkingStarts[start.roundID] = start
                runPreRoundChecks(start.roundID)
                // Checks that end at once have already answered
                guard checkingStarts[start.roundID] != nil else { return nil }
                return .startRoundChecking(StartRoundChecking(roundID: start.roundID))
            }
        }
        return beginRound(start)
    }

    /// The pre-round checks for a round ended: the round starts and the phone hears the ack, or
    /// the phone hears why it was refused.
    func preRoundChecksFinished(_ roundID: UUID) {
        guard let start = checkingStarts.removeValue(forKey: roundID) else { return }
        switch preRoundCheck(roundID) {
        case .passed:
            _ = beginRound(start)
        case .failed(let reason):
            Log.rounds.error("Round \(roundID) refused: the pre-round checks failed")
            sync.send(.startRoundRefused(StartRoundRefused(roundID: roundID, reason: reason)))
        case .notRun, .running:
            checkingStarts[roundID] = start
        }
    }

    /// Starts recording the round, and confirms it to the phone.
    private func beginRound(_ start: StartRound) -> SyncMessage? {

        let selection: CourseSelection
        do {
            selection = try JSONDecoder().decode(CourseSelection.self, from: start.course.gzipDecompressed())
        } catch {
            Log.sync.error("Could not decode the course for round \(start.roundID): \(String(describing: error))")
            return nil
        }

        Log.rounds.notice("Round \(start.roundID) started by the phone")
        store(RoundSettingsMessage(roundID: start.roundID, debugLogging: start.debugLogging, puttLab: start.puttLab,
                                   greenZone: start.greenZone))

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
                round.displayHole = start.displayHole
                round.pins = start.pins
            }
        } else {
            rounds.update(start.roundID) { round in
                round.status = .active
                round.endedAt = nil
                round.lastSeq = nil
                round.endConfirmed = false
                round.mergeDisplayHole(start.displayHole)
                round.mergePins(start.pins)
            }
        }
        // A stream still on the watch keeps its own base; the phone holds only part of it
        if !streams.hasStream(for: start.roundID) {
            rounds.update(start.roundID) { $0.streamBase = start.streamBase }
        }
        if logs.count(for: start.roundID, device: .watch) == 0 {
            rounds.update(start.roundID) { $0.logBase = start.logBase }
        }
        // The lines from just before the round, such as the workout launch, are read with it
        logs.flush()
        logs.moveRecentLines(into: start.roundID, device: .watch)
        // The workout start that came before the round, and anything else recent
        let recent = pendingEvents.filter { Date().timeIntervalSince($0.timestamp) <= Self.pendingEventAge }
        pendingEvents = []
        if !recent.isEmpty {
            streams.append(recent.map { .event($0) }, roundID: start.roundID)
        }
        rounds.applyStrokes(start.strokes)
        sender.pump()
        // The reply can be lost, and the watch can't send a reply again. The confirmation
        // also goes as its own message, so the phone hears either way.
        let ack = StartRoundAck(roundID: start.roundID)
        sync.send(.startRoundAck(ack))
        return .startRoundAck(ack)
    }

    /// Keeps the phone's settings, which outlive the round for lines and rounds that come
    /// before the next start.
    private func store(_ settings: RoundSettingsMessage) {
        Log.isDebugEnabled = settings.debugLogging
        UserDefaults.standard.set(settings.debugLogging, forKey: Self.debugLoggingKey)
        UserDefaults.standard.set(settings.puttLab, forKey: Self.puttLabKey)
        UserDefaults.standard.set(settings.greenZone, forKey: Self.greenZoneKey)
    }

    /// Settings sent mid-round. Ignored for any round but the active one.
    private func apply(_ settings: RoundSettingsMessage) {
        guard rounds.activeRound?.id == settings.roundID else { return }
        Log.rounds.notice("Settings for round \(settings.roundID): debug \(settings.debugLogging), Putt Lab \(settings.puttLab), green zone \(settings.greenZone) m")
        store(settings)
        onSettings?(settings)
    }

    /// The phone ended the round. Records after its end time are dropped, and the reply
    /// gives the last record so the phone knows when it has everything.
    private func endRequested(_ request: EndRequest) -> EndAck {
        guard let round = rounds.round(request.roundID) else {
            Log.rounds.notice("End request for unknown round \(request.roundID)")
            return EndAck(roundID: request.roundID, lastSeq: nil)
        }
        if round.isActive {
            Log.rounds.notice("Round \(round.id) ended by the phone")
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
    /// and deleted. Each round holds its whole course, so the watch must not keep them round
    /// after round. A resume on the phone sends the round again.
    func pruneFinishedRounds(now: Date = Date()) {
        for round in rounds.rounds where round.status == .ended && round.endConfirmed
            && (round.endedAt.map { now.timeIntervalSince($0) > Self.finishedRoundKeepTime } ?? true)
            && !streams.hasStream(for: round.id) {
            rounds.deleteRound(round.id)
            logs.delete(round.id)
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
