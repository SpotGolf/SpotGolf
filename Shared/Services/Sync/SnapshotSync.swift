import Foundation

/// Keeps the hole timeline and marks the same on both devices. Every change sends the full
/// state, so a lost message is fixed by the next one, and a late or repeated one does no harm:
/// timelines are merged and marks keep the highest version.
@MainActor
final class SnapshotSync {
    private let sync: SyncService
    private let rounds: RoundStore
    /// Only the phone owns marks.
    private let sendsMarks: Bool

    init(sync: SyncService, rounds: RoundStore, sendsMarks: Bool) {
        self.sync = sync
        self.rounds = rounds
        self.sendsMarks = sendsMarks
    }

    func sendTimeline(_ round: Round) {
        guard round.isActive else { return }
        sync.send(.holeTimeline(HoleTimelineMessage(roundID: round.id, entries: round.holeTimeline)))
        updateContext(round)
    }

    func sendMarks(_ round: Round) {
        guard sendsMarks, round.isActive else { return }
        sync.send(.marks(round.marksSnapshot))
        updateContext(round)
    }

    /// The latest state for the other device to receive when it next runs.
    func updateContext(_ round: Round) {
        guard round.isActive else { return }
        sync.updateContext(SyncContext(
            timeline: HoleTimelineMessage(roundID: round.id, entries: round.holeTimeline),
            marks: sendsMarks ? round.marksSnapshot : nil
        ))
    }

    /// Returns true if the timeline changed.
    @discardableResult
    func apply(_ message: HoleTimelineMessage) -> Bool {
        rounds.mergeTimeline(message.entries, roundID: message.roundID)
    }

    @discardableResult
    func apply(_ snapshot: MarksSnapshot) -> Bool {
        guard !sendsMarks else { return false }
        return rounds.applyMarks(snapshot)
    }

    /// Returns the round whose timeline changed, if any.
    @discardableResult
    func apply(_ context: SyncContext) -> UUID? {
        if let marks = context.marks {
            apply(marks)
        }
        if let timeline = context.timeline, apply(timeline) {
            return timeline.roundID
        }
        return nil
    }
}
