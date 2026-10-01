import Foundation

/// Keeps the hole timeline and strokes the same on both devices. Every change sends the full
/// state, so a lost message is fixed by the next one, and a late or repeated one does no harm:
/// timelines are merged and strokes keep the highest version.
@MainActor
final class SnapshotSync {
    private let sync: SyncService
    private let rounds: RoundStore
    /// Only the phone owns strokes.
    private let sendsStrokes: Bool

    init(sync: SyncService, rounds: RoundStore, sendsStrokes: Bool) {
        self.sync = sync
        self.rounds = rounds
        self.sendsStrokes = sendsStrokes
    }

    func sendTimeline(_ round: Round) {
        guard round.isActive else { return }
        sync.send(.holeTimeline(HoleTimelineMessage(roundID: round.id, entries: round.holeTimeline)))
        updateContext(round)
    }

    func sendStrokes(_ round: Round) {
        guard sendsStrokes, round.isActive else { return }
        sync.send(.strokes(round.strokesSnapshot))
        updateContext(round)
    }

    /// The latest state for the other device to receive when it next runs.
    func updateContext(_ round: Round) {
        guard round.isActive else { return }
        sync.updateContext(SyncContext(
            timeline: HoleTimelineMessage(roundID: round.id, entries: round.holeTimeline),
            strokes: sendsStrokes ? round.strokesSnapshot : nil
        ))
    }

    /// Returns true if the timeline changed.
    @discardableResult
    func apply(_ message: HoleTimelineMessage) -> Bool {
        rounds.mergeTimeline(message.entries, roundID: message.roundID)
    }

    @discardableResult
    func apply(_ snapshot: StrokesSnapshot) -> Bool {
        guard !sendsStrokes else { return false }
        return rounds.applyStrokes(snapshot)
    }

    /// Returns the round whose timeline changed, if any.
    @discardableResult
    func apply(_ context: SyncContext) -> UUID? {
        if let strokes = context.strokes {
            apply(strokes)
        }
        if let timeline = context.timeline, apply(timeline) {
            return timeline.roundID
        }
        return nil
    }
}
