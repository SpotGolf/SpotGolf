import Foundation

/// The player's skill, as the shot model takes it: how far their drives turn off the line to
/// the target. It is the standard deviation of the angle, in degrees, from published data for
/// golfers of the player's average score. Every club's pattern comes from it. The numbers are in
/// `DispersionConstants`. See plans/2026-11-11-shot-dispersion.md, section 3.
enum MissAngle {
    /// Before any ended rounds: Broadie's golfers scoring 84 to 97.
    static let starting = DispersionConstants.startingAngle
    /// The range the published amateur data covers.
    static let lowest = DispersionConstants.skillAngles[0]
    static let highest = DispersionConstants.skillAngles[2]

    /// Whose scores the skill comes from: the player's own, or one of Broadie's three groups.
    /// The Caddie's stats sheet picks it.
    enum Source: String, CaseIterable, Sendable {
        case myScores, low, mid, high

        /// The group's angle. Nil for the player's own scores.
        var degrees: Double? {
            switch self {
            case .myScores: nil
            case .low: DispersionConstants.skillAngles[0]
            case .mid: DispersionConstants.skillAngles[1]
            case .high: DispersionConstants.skillAngles[2]
            }
        }
    }

    /// Through Broadie and Ko's 80 golfers at 5.5° and 100 golfers at 7.9°.
    static func degrees(averageScore: Double?) -> Double {
        guard let averageScore else { return starting }
        let angle = DispersionConstants.angleAtEighty + DispersionConstants.anglePerStroke * (averageScore - 80)
        return min(max(angle, lowest), highest)
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
