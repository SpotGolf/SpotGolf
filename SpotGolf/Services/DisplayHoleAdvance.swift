import CoreLocation
import Foundation

/// Moves the phone's display hole on during a round, from the watch's GPS fixes as they arrive
/// in the stream. The watch moves its own hole from the same fixes with its own rule; the two
/// holes are never sent between the devices, so they can differ.
///
/// A hole the user picked, or a spot they are editing, holds the display hole for
/// `DisplayHole.holdTime`: the advancer still sees every fix, but its move is dropped.
@MainActor
final class DisplayHoleAdvance {
    private let rounds: RoundStore
    private let now: () -> Date
    private var advancer = HoleAdvancer(moving: .displayHole)
    /// The round the advancer's state is for.
    private var roundID: UUID?

    init(rounds: RoundStore, now: @escaping () -> Date = Date.init) {
        self.rounds = rounds
        self.now = now
    }

    /// Takes the fixes of a stream batch, oldest first. Only an active round's hole moves.
    func received(_ fixes: [TrackPoint], roundID: UUID) {
        guard let round = rounds.round(roundID), round.isActive else { return }
        if roundID != self.roundID {
            self.roundID = roundID
            advancer = HoleAdvancer(moving: .displayHole)
        }
        let selection = round.courseSelection
        for fix in fixes {
            let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude),
                                      altitude: fix.altitude ?? 0,
                                      horizontalAccuracy: fix.horizontalAccuracy ?? -1,
                                      verticalAccuracy: fix.altitude == nil ? -1 : 0,
                                      timestamp: fix.timestamp)
            // The hold is the user's, so it runs on the phone's clock: fixes can arrive late
            guard let next = advancer.advance(location: location, courseSelection: selection,
                                              holeIndex: round.displayHoleIndex),
                  !round.isDisplayHoleHeld(at: now()) else { continue }
            rounds.setDisplayHole(next, roundID: roundID, at: now())
        }
    }
}
