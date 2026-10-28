import Foundation

/// Keeps the display hole, pins and strokes the same on both devices. Every change sends the full
/// state, so a lost message is fixed by the next one, and a late or repeated one does no harm: the
/// later display hole and pins win, and strokes keep the highest version.
@MainActor
final class SnapshotSync {
    private let sync: SyncService
    private let rounds: RoundStore
    /// Only the phone owns strokes.
    private let sendsStrokes: Bool
    /// The settings the watch follows, for the context. Only the phone has them.
    var roundSettings: (Round) -> RoundSettingsMessage? = { _ in nil }

    init(sync: SyncService, rounds: RoundStore, sendsStrokes: Bool) {
        self.sync = sync
        self.rounds = rounds
        self.sendsStrokes = sendsStrokes
    }

    func sendDisplayHole(_ round: Round) {
        guard round.isActive else { return }
        sync.send(.displayHole(DisplayHoleMessage(round: round)))
        updateContext(round)
    }

    func sendPins(_ round: Round) {
        guard round.isActive else { return }
        sync.send(.pins(PinsMessage(roundID: round.id, pins: round.pins)))
        updateContext(round)
    }

    func sendStrokes(_ round: Round) {
        guard sendsStrokes, round.isActive else { return }
        sync.send(.strokes(round.strokesSnapshot))
        updateContext(round)
    }

    /// Phone: the settings the watch follows, sent when the round is opened.
    func sendSettings(_ round: Round) {
        guard round.isActive, let settings = roundSettings(round) else { return }
        sync.send(.settings(settings))
        updateContext(round)
    }

    /// The latest state for the other device to receive when it next runs.
    func updateContext(_ round: Round) {
        guard round.isActive else { return }
        sync.updateContext(SyncContext(
            displayHole: DisplayHoleMessage(round: round),
            pins: PinsMessage(roundID: round.id, pins: round.pins),
            strokes: sendsStrokes ? round.strokesSnapshot : nil,
            settings: roundSettings(round)
        ))
    }

    /// Returns true if the display hole changed.
    @discardableResult
    func apply(_ message: DisplayHoleMessage) -> Bool {
        rounds.mergeDisplayHole(message.displayHole, heldUntil: message.heldUntil, roundID: message.roundID)
    }

    /// Returns true if any pin changed.
    @discardableResult
    func apply(_ message: PinsMessage) -> Bool {
        rounds.mergePins(message.pins, roundID: message.roundID)
    }

    @discardableResult
    func apply(_ snapshot: StrokesSnapshot) -> Bool {
        guard !sendsStrokes else { return false }
        return rounds.applyStrokes(snapshot)
    }

    func apply(_ context: SyncContext) {
        if let strokes = context.strokes {
            apply(strokes)
        }
        if let displayHole = context.displayHole {
            apply(displayHole)
        }
        if let pins = context.pins {
            apply(pins)
        }
    }
}
