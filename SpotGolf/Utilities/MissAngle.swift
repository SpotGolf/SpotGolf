import Foundation

/// How far the player's shots turn off the line to the target: the standard deviation of the
/// angle, in degrees, from published data for golfers of the player's average score. See
/// plans/2026-11-02-caddie-club-and-aim.md, section 2.
enum MissAngle {
    /// Before any ended rounds: Broadie's golfers scoring 84 to 97.
    static let starting = 6.4
    /// The range the published amateur data covers.
    static let lowest = 5.4
    static let highest = 8.1

    /// Through Broadie and Ko's 80 golfers at 5.5° and 100 golfers at 7.9°.
    static func degrees(averageScore: Double?) -> Double {
        guard let averageScore else { return starting }
        return min(max(5.5 + 0.12 * (averageScore - 80), lowest), highest)
    }

    static func degrees(for rounds: [Round]) -> Double {
        degrees(averageScore: averageScore(of: rounds))
    }

    /// The average strokes per hole, penalty strokes included, over every hole with strokes in an
    /// ended round, times 18. That counts 9-hole and partly played rounds at 18 holes. Nil
    /// without any.
    static func averageScore(of rounds: [Round]) -> Double? {
        let holes = rounds.filter { $0.status == .ended }.flatMap(\.holes).filter { !$0.strokes.isEmpty }
        guard !holes.isEmpty else { return nil }
        return 18 * Double(holes.reduce(0) { $0 + $1.strokeCount }) / Double(holes.count)
    }
}
