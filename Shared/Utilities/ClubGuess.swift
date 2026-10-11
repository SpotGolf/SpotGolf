import Foundation

/// Guesses the club for a stroke from where it is. See plans/2026-10-11-club-selection.md.
enum ClubGuess {
    /// The putter on the green. Otherwise the club in the bag whose distance is nearest the yards
    /// to the target, with a tie going to the longer club; beyond the longest club that is the
    /// longest, and inside the shortest it is the shortest. The driver is only guessed off the
    /// tee. Without yards, a tee shot gets the longest club and anything else no guess.
    static func club(in bag: GolfBag, yardsToTarget: Int?, isOnGreen: Bool, isTeeShot: Bool) -> Club? {
        if isOnGreen, let putter = bag.clubs.first(where: { $0.kind == .putter }) {
            return putter
        }
        let candidates = bag.clubs
            .filter { isTeeShot || $0.id != "dr" }
            .compactMap { club in bag.distance(of: club).map { (club: club, distance: $0) } }
        guard !candidates.isEmpty else { return nil }
        let longest = candidates.max { $0.distance < $1.distance }!
        guard let yards = yardsToTarget else {
            return isTeeShot ? longest.club : nil
        }
        return candidates.min { a, b in
            let gapA = abs(a.distance - yards), gapB = abs(b.distance - yards)
            return gapA != gapB ? gapA < gapB : a.distance > b.distance
        }!.club
    }
}
