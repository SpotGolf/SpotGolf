import Foundation

/// Every number the shot model runs on, each marked as published, with its source, or as an
/// assumption of ours. See plans/2026-11-11-shot-dispersion.md, section 3.
///
/// Sources:
/// - Broadie (2008), "Assessing Golfer Performance Using Golfmetrics", Science and Golf V.
/// - Broadie and Ko (2009), "A Simulation Model to Analyze the Impact of Distance and Direction
///   on Golf Scores", Winter Simulation Conference.
enum DispersionConstants {
    // MARK: - Skill

    /// Published (Broadie 2008, Table 1): the driver angle spread, in degrees, of golfers scoring
    /// 70–83, 84–97 and 98–120. Every other table here has one value for each of these three.
    static let skillAngles = [5.4, 6.4, 8.1]
    /// Published (Broadie 2008, Table 1): each group's 75th-percentile drive, in yards. Used by
    /// the tests only: the app takes each club's distance from the Caddie.
    static let skillDrives = [248.0, 237.0, 216.0]
    /// Published (Broadie and Ko 2009, Table 2): the angle spread runs through 5.5° for golfers
    /// averaging 80 and 7.9° for golfers averaging 100.
    static let angleAtEighty = 5.5
    static let anglePerStroke = 0.12
    /// Assumption: before any ended rounds, the middle group.
    static let startingAngle = 6.4

    // MARK: - Distance error

    /// Assumption (Broadie and Ko describe the curve but give no numbers): the share of good
    /// shots, and the good and bad shots' bell curves, before the whole is standardized.
    static let goodShare = 0.85
    static let goodMean = 0.25
    static let goodSpread = 0.55
    static let badMean = -1.6
    static let badSpread = 1.0
    /// Assumption: the standardized error's mean, a little short.
    static let errorMean = -0.15
    /// Assumption: no shot goes less than this share of the full distance.
    static let shortestShare = 0.2

    // MARK: - Spreads by club

    /// Assumption (Broadie and Ko say only that it grows as skill drops): the driver's distance
    /// spread, as a share of its full distance, for each skill group.
    static let driverDistanceSpreads = [0.09, 0.10, 0.13]

    /// Published (Broadie 2008, Table 2): the median distance from the hole after a 100–150 yard
    /// shot from the fairway, as a share of the shot's length, for each skill group.
    static let fairwayMisses = [0.087, 0.120, 0.173]
    /// Published (Broadie 2008, Table 2): the same from the rough. Logged by the tests, not used.
    static let roughMisses = [0.104, 0.135, 0.184]
    /// Assumption: the shot length the fairway misses are matched at, the middle of 100–150.
    static let approachYards = 125.0
    /// Assumption: a full shot's distance spread over its angle spread in radians.
    static let approachDepthToLateral = 1.5
    /// Solved by `DispersionCalibrationTests` from the four values above: every club's but the
    /// driver's angle spread, in degrees, and distance spread, for each skill group.
    static let approachAngles = [3.98, 5.49, 7.91]
    static let approachDistanceSpreads = [0.104, 0.144, 0.207]

    /// Published (Broadie 2008): inside 60 yards, amateurs' distance error is about 3.2 times
    /// their direction error.
    static let shortDepthToLateral = 3.2
    /// A club that averages under this many yards is a short shot.
    static let shortYards = 60.0
    /// Assumption: short shots are matched to the fairway misses too, at this length.
    static let shortCalibrationYards = 50.0
    /// Solved by `DispersionCalibrationTests`, as the approach values are.
    static let shortAngles = [2.57, 3.55, 5.12]
    static let shortDistanceSpreads = [0.144, 0.198, 0.286]

    // MARK: - Lie

    /// Assumption (Broadie and Ko say only that the distance spread is larger from the rough and
    /// larger again from sand): what the distance spread is multiplied by.
    static let roughSpread = 1.25
    static let sandSpread = 1.6

    // MARK: - Working it out

    /// The shots a shape's regions are worked out from, and their seed.
    static let shapeShots = 150_000
    static let shapeSeed: UInt64 = 7
    /// The share of shots each region holds, smallest first.
    static let regionShares = [0.5, 0.8, 0.95]
    /// The regions are found at this full distance, in yards, on a grid of squares `gridYards`
    /// wide, blurred by `blurSquares` squares, with their outlines kept to within `outlineYards`.
    static let shapeYards = 200.0
    static let gridYards = 1.0
    static let blurSquares = 3.0
    static let outlineYards = 0.5
    /// The shots the outcome chances are counted over.
    static let outcomeShots = 2_000
}
