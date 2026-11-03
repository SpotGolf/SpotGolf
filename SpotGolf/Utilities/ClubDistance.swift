import Foundation

/// How far the player hits one club: a starting estimate from the bag's distance, moved toward
/// the player's own shots as they add up. See plans/2026-11-02-caddie-club-distances.md,
/// section 3.
struct ClubDistance: Equatable {
    /// The starting short spread, as a share of the starting distance. Larger than the long one
    /// because mishits come up short far more often than long.
    static let startingShortSpread = 0.12
    /// The starting long spread, as a share of the starting distance.
    static let startingLongSpread = 0.08
    /// How many shots the starting estimate counts as.
    static let startingWeight = 5.0

    /// In yards.
    let average: Int
    /// The ends of the range where about two in three shots land, in yards.
    let low: Int
    let high: Int
    /// How many of the player's shots it comes from.
    let shots: Int

    /// `startingDistance` is the bag's distance for the club, and `shots` the yards of each
    /// counted shot.
    init(startingDistance: Int, shots: [Double]) {
        let start = Double(startingDistance)
        let weight = Self.startingWeight
        let total = weight + Double(shots.count)
        let average = (weight * start + shots.reduce(0, +)) / total
        // Each side gets only about half the shots, so each shot's gap counts twice on its side
        let shortSquares = shots.filter { $0 < average }.reduce(0) { $0 + 2 * pow(average - $1, 2) }
        let longSquares = shots.filter { $0 > average }.reduce(0) { $0 + 2 * pow($1 - average, 2) }
        let shortSpread = ((weight * pow(Self.startingShortSpread * start, 2) + shortSquares) / total).squareRoot()
        let longSpread = ((weight * pow(Self.startingLongSpread * start, 2) + longSquares) / total).squareRoot()
        self.average = Int(average.rounded())
        low = Int((average - shortSpread).rounded())
        high = Int((average + longSpread).rounded())
        self.shots = shots.count
    }
}
