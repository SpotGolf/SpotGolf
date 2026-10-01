import Foundation

/// The phone's side of the messaging: starting and ending rounds with the watch, receiving
/// the watch's stream, and keeping the timeline and strokes in step.
@MainActor
final class PhoneSync: ObservableObject {
    /// How long the phone waits for the watch to confirm a start before offering Retry.
    nonisolated static let defaultStartTimeout: TimeInterval = 15

    /// How long the phone waits before sending a failed start or end request again.
    nonisolated static let defaultRetryDelay: TimeInterval = 5

    /// While GPS arrives, the hole starts are worked out at most this often.
    nonisolated static let defaultTimelineFixInterval: TimeInterval = 5

    enum StartState: Equatable {
        case waiting
        /// No confirmation in time: the user can retry or cancel.
        case timedOut
    }

    /// Rounds that are starting, and whether they are still waiting.
    @Published private(set) var startStates: [UUID: StartState] = [:]

    let sync: SyncService
    let rounds: RoundStore
    let streams: StreamStore
    let suggestions: SuggestionStore
    let receiver: StreamReceiver
    let snapshots: SnapshotSync

    /// False only for UI tests, which run without a watch: rounds start and end on the phone alone.
    private let requiresWatch: Bool
    private let startTimeout: TimeInterval
    private let retryDelay: TimeInterval
    private let timelineFixInterval: TimeInterval
    // When each round's hole starts were last worked out from arriving GPS
    private var lastTimelineFix: [UUID: Date] = [:]
    /// Launches the watch app so it can take the round. `HKHealthStore.startWatchApp` in the app.
    private let launchWatchApp: () -> Void
    private var startTimers: [UUID: Timer] = [:]
    private var retryTimers: [UUID: Timer] = [:]

    init(sync: SyncService, rounds: RoundStore, streams: StreamStore, suggestions: SuggestionStore,
         requiresWatch: Bool = true, startTimeout: TimeInterval = PhoneSync.defaultStartTimeout,
         retryDelay: TimeInterval = PhoneSync.defaultRetryDelay,
         timelineFixInterval: TimeInterval = PhoneSync.defaultTimelineFixInterval,
         launchWatchApp: @escaping () -> Void = {}) {
        self.sync = sync
        self.rounds = rounds
        self.streams = streams
        self.suggestions = suggestions
        self.requiresWatch = requiresWatch
        self.startTimeout = startTimeout
        self.retryDelay = retryDelay
        self.timelineFixInterval = timelineFixInterval
        self.launchWatchApp = launchWatchApp
        receiver = StreamReceiver(rounds: rounds, streams: streams)
        snapshots = SnapshotSync(sync: sync, rounds: rounds, sendsStrokes: true)

        sync.handler = { [weak self] message in self?.handle(message) }
        rounds.onTimelineChanged = { [weak self] round in
            self?.snapshots.sendTimeline(round)
            self?.fixTimeline(round.id)
        }
        rounds.onStrokesChanged = { [weak self] round in
            self?.snapshots.sendStrokes(round)
        }
        sync.onReachabilityChange { [weak self] in self?.reachabilityChanged() }

        // A round left starting when the app quit is waiting for a confirmation no one tracks
        for round in rounds.rounds where round.status == .starting {
            startStates[round.id] = .timedOut
        }
    }

    // MARK: - Start

    /// Adds a round and asks the watch to start it. It becomes active once the watch confirms.
    @discardableResult
    func startRound(courseSelection: CourseSelection) -> UUID {
        let round = rounds.startRound(courseSelection: courseSelection, status: .starting)
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
        suggestions.deleteRound(roundID)
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
            print("[Sync] Could not encode course: \(error)")
            sync.syncError = "Could not send the round to the watch."
            return
        }
        let start = StartRound(roundID: round.id, date: round.date, course: course,
                               holeTimeline: round.holeTimeline, strokes: round.strokesSnapshot,
                               streamBase: receiver.have(for: round.id))
        sync.send(.startRound(start), reply: { [weak self] reply in
            if case .startRoundAck(let ack) = reply {
                self?.started(ack.roundID)
            }
        }, failure: { [weak self] error in
            // Sent again after a short wait, and when the watch becomes reachable, until the timeout
            print("[Sync] Start round failed: \(error)")
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
        rounds.update(roundID) { round in
            round.status = .active
            round.resumedFromEnd = nil
        }
        if let round = rounds.round(roundID) {
            snapshots.updateContext(round)
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
        finish(roundID)
    }

    private func sendEndRequest(_ roundID: UUID) {
        guard let round = rounds.round(roundID), round.status == .ending, !round.endConfirmed,
              let endedAt = round.endedAt else { return }
        sync.send(.endRequest(EndRequest(roundID: roundID, endedAt: endedAt)), reply: { [weak self] reply in
            if case .endAck(let ack) = reply {
                self?.watchEnded(ack.roundID, lastSeq: ack.lastSeq)
            }
        }, failure: { [weak self] error in
            print("[Sync] End request failed: \(error)")
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
        rounds.update(roundID) { $0.end(at: Date()) }
        // The timeline first: it decides which hole each swing is on
        fixTimeline(roundID)
    }

    // MARK: - Import

    /// Adds an active round read from an export, with its stream, and works out its hole starts.
    /// Returns false when another round is in progress, since only one can be.
    @discardableResult
    func importRound(_ round: Round, records: [StreamRecord]) -> Bool {
        guard rounds.currentRound == nil else { return false }
        rounds.rounds.insert(round, at: 0)
        streams.append(records, roundID: round.id)
        fixTimeline(round.id)
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
            fixTimelineThrottled(batch.roundID)
            return .streamAck(ack)
        case .holeTimeline(let timeline):
            if snapshots.apply(timeline) {
                fixTimeline(timeline.roundID)
            }
            return nil
        case .context(let context):
            if let roundID = snapshots.apply(context) {
                fixTimeline(roundID)
            }
            return nil
        case .startRoundAck(let ack):
            started(ack.roundID)
            return nil
        case .endAck(let ack):
            watchEnded(ack.roundID, lastSeq: ack.lastSeq)
            return nil
        case .startRound, .cancelRound, .endRequest, .streamAck, .strokes, .chunk:
            return nil
        }
    }

    private func receiveEndRound(_ end: EndRound) {
        guard let round = rounds.round(end.roundID) else { return }
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

    // MARK: - Timeline

    /// Works out the hole starts from the GPS path (see `StrokeFinder.holeStarts`), and sends any change.
    func fixTimeline(_ roundID: UUID) {
        guard let round = rounds.round(roundID) else { return }
        lastTimelineFix[roundID] = Date()
        let fixed = StrokeFinder.holeStarts(round: round,
                                            points: streams.points(for: roundID, until: round.endedAt),
                                            swings: streams.swings(for: roundID, until: round.endedAt))
        if fixed != round.holeTimeline {
            rounds.setTimeline(fixed, roundID: roundID)
        }
    }

    /// `fixTimeline`, at most once every `timelineFixInterval`: GPS arrives about once a second.
    private func fixTimelineThrottled(_ roundID: UUID) {
        if let last = lastTimelineFix[roundID], Date().timeIntervalSince(last) < timelineFixInterval { return }
        fixTimeline(roundID)
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
                sync.send(.streamAck(StreamAck(roundID: round.id, have: receiver.have(for: round.id))))
            case .ending:
                sendEndRequest(round.id)
                sync.send(.streamAck(StreamAck(roundID: round.id, have: receiver.have(for: round.id))))
            default:
                break
            }
        }
    }
}
