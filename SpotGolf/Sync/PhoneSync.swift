import Foundation
import Observation
import os

/// The phone's side of the messaging: starting and ending rounds with the watch, receiving
/// the watch's stream, and keeping the timeline and strokes in step.
@MainActor
@Observable
final class PhoneSync {
    /// How long the phone waits before sending a failed start or end request again.
    nonisolated static let defaultRetryDelay: TimeInterval = 5

    enum StartState: Equatable {
        case waiting
        /// No confirmation in time: the user can retry or cancel.
        case timedOut
        /// The watch refused until these are granted on it: the user can retry or cancel.
        case needsPermissions([AppPermission])
        /// The watch app is on another version: the user installs this version on the watch,
        /// then retries, or cancels.
        case needsWatchUpdate(watchVersion: String)
    }

    /// Rounds that are starting, and whether they are still waiting.
    private(set) var startStates: [UUID: StartState] = [:]

    /// This app's version, sent with each start; the watch refuses any other. Tests set it.
    @ObservationIgnored var version = AppVersion.text()

    let sync: SyncService
    let rounds: RoundStore
    let streams: StreamStore
    let logs: LogStore
    let receiver: StreamReceiver
    let snapshots: SnapshotSync

    /// False only for UI tests, which run without a watch: rounds start and end on the phone alone.
    private let requiresWatch: Bool
    private let startTimeout: TimeInterval
    private let retryDelay: TimeInterval
    /// Launches the watch app so it can take the round. `HKHealthStore.startWatchApp` in the app.
    private let launchWatchApp: () -> Void
    /// The Debug Logging setting, sent to the watch with each start. Tests set it.
    @ObservationIgnored var debugLogging: () -> Bool = { false }
    private var startTimers: [UUID: Timer] = [:]
    private var retryTimers: [UUID: Timer] = [:]

    init(sync: SyncService, rounds: RoundStore, streams: StreamStore, logs: LogStore,
         requiresWatch: Bool = true, startTimeout: TimeInterval = SyncService.startTimeout,
         retryDelay: TimeInterval = PhoneSync.defaultRetryDelay,
         launchWatchApp: @escaping () -> Void = {}) {
        self.sync = sync
        self.rounds = rounds
        self.streams = streams
        self.logs = logs
        self.requiresWatch = requiresWatch
        self.startTimeout = startTimeout
        self.retryDelay = retryDelay
        self.launchWatchApp = launchWatchApp
        receiver = StreamReceiver(rounds: rounds, streams: streams, logs: logs)
        snapshots = SnapshotSync(sync: sync, rounds: rounds, sendsStrokes: true)

        sync.handler = { [weak self] message in self?.handle(message) }
        rounds.addListener { [weak self] event in self?.roundChanged(event) }
        sync.onReachabilityChange { [weak self] in self?.reachabilityChanged() }

        // A round left starting when the app quit is waiting for a confirmation no one tracks
        for round in rounds.rounds where round.status == .starting {
            startStates[round.id] = .timedOut
        }
    }

    /// Sends changes made on the phone to the watch.
    private func roundChanged(_ event: RoundEvent) {
        switch event {
        case .timelineChanged(let round): snapshots.sendTimeline(round)
        case .displayHoleChanged(let round): snapshots.sendDisplayHole(round)
        case .pinsChanged(let round): snapshots.sendPins(round)
        case .strokesChanged(let round): snapshots.sendStrokes(round)
        case .roundsChanged: break
        }
    }

    // MARK: - Start

    /// Adds a round and asks the watch to start it. It becomes active once the watch confirms.
    @discardableResult
    func startRound(courseSelection: CourseSelection) -> UUID {
        let round = rounds.startRound(courseSelection: courseSelection, status: .starting)
        Log.rounds.notice("Round \(round.id) starting")
        beginStart(round.id)
        return round.id
    }

    /// Resumes an ended round, through the same handshake as a new one.
    func resumeRound(_ roundID: UUID) {
        guard rounds.currentRound == nil, rounds.round(roundID)?.status == .ended else { return }
        rounds.update(roundID) { round in
            round.status = .starting
            round.resumedFromEnd = round.endedAt
            round.endedAt = nil
            round.lastSeq = nil
            round.endConfirmed = false
        }
        beginStart(roundID)
    }

    func retryStart(_ roundID: UUID) {
        guard rounds.round(roundID)?.status == .starting else { return }
        beginStart(roundID)
    }

    /// Gives up on a round that has not started. If the watch did start it, it deletes it.
    /// A resumed round goes back to ended instead, and keeps its data.
    func cancelStart(_ roundID: UUID) {
        guard let round = rounds.round(roundID), round.status == .starting else { return }
        Log.rounds.notice("Round \(roundID) start cancelled")
        stopWaiting(roundID)
        if let endedAt = round.resumedFromEnd {
            rounds.update(roundID) { round in
                round.status = .ended
                round.endedAt = endedAt
                round.resumedFromEnd = nil
                round.endConfirmed = false
            }
            // If the watch did resume it, it ends it again and says where its stream ends
            let request = SyncMessage.endRequest(EndRequest(roundID: roundID, endedAt: endedAt))
            sync.send(request, reply: { [weak self] reply in
                if case .endAck(let ack) = reply {
                    self?.watchEnded(ack.roundID, lastSeq: ack.lastSeq)
                }
            })
            sync.queue(request)
            return
        }
        rounds.deleteRound(roundID)
        streams.delete(roundID)
        logs.delete(roundID)
        let message = SyncMessage.cancelRound(CancelRound(roundID: roundID))
        sync.send(message)
        sync.queue(message)
    }

    private func beginStart(_ roundID: UUID) {
        guard requiresWatch else {
            rounds.update(roundID) { $0.status = .starting }
            started(roundID)
            return
        }
        startStates[roundID] = .waiting
        startTimers[roundID]?.invalidate()
        startTimers[roundID] = Timer.scheduledTimer(withTimeInterval: startTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.startStates[roundID] == .waiting else { return }
                Log.rounds.error("Round \(roundID): watch did not confirm the start in time")
                self.startStates[roundID] = .timedOut
            }
        }
        launchWatchApp()
        sendStart(roundID)
    }

    private func sendStart(_ roundID: UUID) {
        guard let round = rounds.round(roundID), round.status == .starting else { return }
        let course: Data
        do {
            course = try JSONEncoder().encode(round.courseSelection.trimmed).gzipCompressed()
        } catch {
            Log.sync.error("Could not encode the course for round \(roundID): \(String(describing: error))")
            sync.syncError = String(localized: "Could not send the round to the watch.")
            return
        }
        let start = StartRound(roundID: round.id, date: round.date, course: course,
                               holeTimeline: round.holeTimeline, displayHole: round.displayHole,
                               pins: round.pins,
                               strokes: round.strokesSnapshot,
                               streamBase: receiver.have(for: round.id),
                               version: version,
                               logBase: receiver.haveLogs(for: round.id),
                               debugLogging: debugLogging())
        sync.send(.startRound(start), reply: { [weak self] reply in
            switch reply {
            case .startRoundAck(let ack): self?.started(ack.roundID)
            case .startRoundRefused(let refused): self?.refused(refused)
            default: break
            }
        }, failure: { [weak self] _ in
            // SyncService logs the failure. Sent again after a short wait, and when the watch
            // becomes reachable, until the timeout
            self?.retryLater(roundID)
        })
    }

    /// Sends a failed start or end request again after `retryDelay`, while it is still needed.
    private func retryLater(_ roundID: UUID) {
        guard retryTimers[roundID] == nil else { return }
        retryTimers[roundID] = Timer.scheduledTimer(withTimeInterval: retryDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.retryTimers[roundID] = nil
                guard let round = self.rounds.round(roundID) else { return }
                switch round.status {
                case .starting where self.startStates[roundID] == .waiting:
                    self.sendStart(roundID)
                case .ending:
                    self.sendEndRequest(roundID)
                default:
                    break
                }
            }
        }
    }

    private func started(_ roundID: UUID) {
        guard rounds.round(roundID)?.status == .starting else { return }
        stopWaiting(roundID)
        Log.rounds.notice("Round \(roundID) active: watch confirmed")
        rounds.update(roundID) { round in
            round.status = .active
            round.resumedFromEnd = nil
        }
        // Holes without a pin show the green's center until a real pin is known
        rounds.addCenterPins(roundID: roundID)
        if let round = rounds.round(roundID) {
            snapshots.updateContext(round)
        }
    }

    /// The watch refused the round. It waits for the user to retry or cancel.
    private func refused(_ refused: StartRoundRefused) {
        guard rounds.round(refused.roundID)?.status == .starting else { return }
        startTimers.removeValue(forKey: refused.roundID)?.invalidate()
        switch refused.reason {
        case .missingPermissions(let missing):
            Log.rounds.error("Round \(refused.roundID): watch is missing \(missing.map(\.rawValue).joined(separator: ", "))")
            startStates[refused.roundID] = .needsPermissions(missing)
        case .versionMismatch(let watchVersion):
            Log.rounds.error("Round \(refused.roundID): watch app is version \(watchVersion), this app \(self.version)")
            startStates[refused.roundID] = .needsWatchUpdate(watchVersion: watchVersion)
        }
    }

    private func stopWaiting(_ roundID: UUID) {
        startTimers.removeValue(forKey: roundID)?.invalidate()
        startStates.removeValue(forKey: roundID)
    }

    // MARK: - End

    /// Ends the round on the phone. It stays ending until the watch's stream has fully arrived.
    func endRound(_ roundID: UUID) {
        guard let round = rounds.round(roundID) else { return }
        switch round.status {
        case .starting:
            cancelStart(roundID)
        case .active:
            Log.rounds.notice("Round \(roundID) ending on the phone")
            rounds.update(roundID) { round in
                round.status = .ending
                round.endedAt = Date()
            }
            guard requiresWatch else {
                finish(roundID)
                return
            }
            sendEndRequest(roundID)
            // The queued copy reaches the watch even if it is not running now
            if let endedAt = rounds.round(roundID)?.endedAt {
                sync.queue(.endRequest(EndRequest(roundID: roundID, endedAt: endedAt)))
            }
        case .ending, .ended:
            break
        }
    }

    /// Ends the round now, without waiting for the watch. Late records up to the end time are still kept.
    func forceEnd(_ roundID: UUID) {
        guard rounds.round(roundID)?.status == .ending else { return }
        Log.rounds.notice("Round \(roundID) force ended before the watch sent everything")
        finish(roundID)
    }

    private func sendEndRequest(_ roundID: UUID) {
        guard let round = rounds.round(roundID), round.status == .ending, !round.endConfirmed,
              let endedAt = round.endedAt else { return }
        sync.send(.endRequest(EndRequest(roundID: roundID, endedAt: endedAt)), reply: { [weak self] reply in
            if case .endAck(let ack) = reply {
                self?.watchEnded(ack.roundID, lastSeq: ack.lastSeq)
            }
        }, failure: { [weak self] _ in
            // SyncService logs the failure
            self?.retryLater(roundID)
        })
    }

    /// The watch has ended the round, and `lastSeq` is its last record.
    private func watchEnded(_ roundID: UUID, lastSeq: Int?) {
        rounds.update(roundID) { round in
            if let lastSeq {
                round.lastSeq = lastSeq
            }
            round.endConfirmed = true
        }
        // Records past the watch's last one were dropped on the watch. Nil also means the
        // watch no longer knows the round, so nothing is removed then.
        if let lastSeq {
            streams.truncate(roundID, to: lastSeq + 1)
        }
        finishIfComplete(roundID)
    }

    /// An ending round is done once every record up to the watch's last one has arrived.
    private func finishIfComplete(_ roundID: UUID) {
        guard let round = rounds.round(roundID), round.status == .ending, round.endConfirmed,
              receiver.have(for: roundID) > (round.lastSeq ?? -1) else { return }
        finish(roundID)
    }

    private func finish(_ roundID: UUID) {
        Log.rounds.notice("Round \(roundID) ended, \(self.receiver.have(for: roundID)) records")
        rounds.update(roundID) { $0.end(at: Date()) }
    }

    // MARK: - Import

    /// Adds an active round read from an export, with its stream.
    /// Returns false when another round is in progress, since only one can be.
    @discardableResult
    func importRound(_ round: Round, records: [StreamRecord]) -> Bool {
        guard rounds.currentRound == nil else { return false }
        rounds.add(round)
        rounds.addCenterPins(roundID: round.id)
        streams.append(records, roundID: round.id)
        return true
    }

    // MARK: - Receive

    private func handle(_ message: SyncMessage) -> SyncMessage? {
        switch message {
        case .endRound(let end):
            receiveEndRound(end)
            return .endAck(EndAck(roundID: end.roundID, lastSeq: nil))
        case .streamBatch(let batch):
            let ack = receiver.receive(batch)
            finishIfComplete(batch.roundID)
            return .streamAck(ack)
        case .holeTimeline(let timeline):
            snapshots.apply(timeline)
            return nil
        case .displayHole(let displayHole):
            snapshots.apply(displayHole)
            return nil
        case .pins(let pins):
            snapshots.apply(pins)
            return nil
        case .context(let context):
            snapshots.apply(context)
            return nil
        case .startRoundAck(let ack):
            started(ack.roundID)
            return nil
        case .startRoundRefused(let refused):
            self.refused(refused)
            return nil
        case .endAck(let ack):
            watchEnded(ack.roundID, lastSeq: ack.lastSeq)
            return nil
        case .startRound, .cancelRound, .endRequest, .streamAck, .strokes, .chunk:
            return nil
        }
    }

    private func receiveEndRound(_ end: EndRound) {
        guard let round = rounds.round(end.roundID) else {
            Log.rounds.error("Watch ended unknown round \(end.roundID)")
            return
        }
        Log.rounds.notice("Round \(end.roundID) ended on the watch")
        rounds.update(end.roundID) { round in
            if round.status == .starting || round.status == .active {
                round.status = .ending
            }
            if round.endedAt == nil {
                round.endedAt = end.endedAt
            }
        }
        if round.status == .starting {
            stopWaiting(end.roundID)
        }
        watchEnded(end.roundID, lastSeq: end.lastSeq)
    }

    // MARK: - Reachability

    private func reachabilityChanged() {
        guard sync.transport.isReachable else { return }
        for round in rounds.rounds {
            switch round.status {
            case .starting where startStates[round.id] == .waiting:
                sendStart(round.id)
            case .active:
                // Tells the watch where to continue, without waiting for its next fix
                sync.send(.streamAck(receiver.ack(for: round.id)))
            case .ending:
                sendEndRequest(round.id)
                sync.send(.streamAck(receiver.ack(for: round.id)))
            default:
                break
            }
        }
    }
}
