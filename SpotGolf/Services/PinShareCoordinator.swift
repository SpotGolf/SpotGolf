import Foundation
import Combine
import os

/// Shares pins with other golfers on the same course. When a round starts or resumes, whether it
/// shares pins is decided once: only with an iCloud account and "Share Pin Locations" on. A
/// sharing round fetches the day's shared pins then, and again each time the display moves past
/// the furthest hole shown, the end of a hole, and uploads the pins the player sets on either
/// device from then on, never ones set while the round was not sharing. Nothing is tried again:
/// a failed fetch or upload is only logged. See plans/2026-10-06-shared-pins.md.
@MainActor
final class PinShareCoordinator: ObservableObject {
    private let rounds: RoundStore
    private let sharing: PinSharing
    private let sharesPins: () -> Bool
    private let now: () -> Date
    private var cancellable: AnyCancellable?
    private var checkScheduled = false

    /// Per active round, the furthest hole shown.
    private var furthestHole: [UUID: Int] = [:]
    /// Per active round that shares pins, when it started sharing. Missing for a round that does
    /// not share, and while the iCloud account is checked.
    private var sharingSince: [UUID: Date] = [:]
    /// Per round and hole, the time of the set pin last uploaded.
    private var uploads: [UUID: [Int: Date]] = [:]

    init(rounds: RoundStore, sharing: PinSharing, sharesPins: @escaping () -> Bool, now: @escaping () -> Date = Date.init) {
        self.rounds = rounds
        self.sharing = sharing
        self.sharesPins = sharesPins
        self.now = now
        // Changes from both devices: a round started, the display hole moved, a pin set
        cancellable = rounds.$rounds.sink { [weak self] _ in self?.scheduleCheck() }
    }

    /// `rounds` publishes before it changes, so the check runs once the change is in.
    private func scheduleCheck() {
        guard !checkScheduled else { return }
        checkScheduled = true
        Task { [weak self] in
            guard let self else { return }
            checkScheduled = false
            await check()
        }
    }

    /// Starts sharing for rounds that just started or resumed, fetches at the end of a hole, and
    /// uploads new pins. Returns once all of it is done.
    func check() async {
        let active = rounds.rounds.filter(\.isActive)
        // A round that ends and resumes starts over
        furthestHole = furthestHole.filter { id, _ in active.contains { $0.id == id } }
        sharingSince = sharingSince.filter { id, _ in active.contains { $0.id == id } }
        for round in active {
            let shown = round.displayHoleIndex
            if let furthest = furthestHole[round.id] {
                if shown > furthest {
                    furthestHole[round.id] = shown
                    await fetch(round.id)
                }
            } else {
                furthestHole[round.id] = shown
                await decideSharing(round.id)
            }
            if let round = rounds.round(round.id) {
                await upload(round)
            }
        }
    }

    /// Decides once whether a round that just started or resumed shares pins, and fetches if it does.
    private func decideSharing(_ roundID: UUID) async {
        let switchedOn = sharesPins()
        let startedAt = now()
        let shares = switchedOn ? await sharing.isAccountAvailable() : false
        Log.pins.notice("Round \(roundID, privacy: .public) \(shares ? "shares" : "does not share", privacy: .public) pins")
        guard shares else { return }
        sharingSince[roundID] = startedAt
        await fetch(roundID)
    }

    // MARK: - Fetch

    private func fetch(_ roundID: UUID) async {
        guard sharingSince[roundID] != nil, let round = rounds.round(roundID) else { return }
        do {
            let shared = try await sharing.fetch(courseID: round.course.id, courseDate: SharedPin.courseDate(for: now()))
            if let round = rounds.round(roundID) {
                rounds.addSharedPins(round.pins(from: shared), roundID: roundID)
            }
        } catch {
            Log.pins.error("Could not fetch shared pins: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Upload

    private func upload(_ round: Round) async {
        guard let since = sharingSince[round.id] else { return }
        for pin in round.pins where pin.source == .set && pin.setAt >= since
            && uploads[round.id]?[pin.holeIndex] != pin.setAt {
            guard let shared = round.sharedPin(for: pin) else { continue }
            uploads[round.id, default: [:]][pin.holeIndex] = pin.setAt
            do {
                try await sharing.upload(shared)
            } catch {
                // The pin stays on this phone and its watch
                Log.pins.error("Could not upload a pin: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
