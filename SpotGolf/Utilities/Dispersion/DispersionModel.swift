import Foundation
import simd

/// What one shot's pattern is made from. See plans/2026-11-11-shot-dispersion.md, section 2.
struct DispersionParams: Equatable, Sendable {
    /// The angle spread: the standard deviation of the shot's direction off the aim, in degrees.
    var sigmaAlphaDeg: Double
    /// The distance spread, as a share of the full distance.
    var sigmaD: Double
    /// The full distance, in yards.
    var dMu: Double

    init(sigmaAlphaDeg: Double, sigmaD: Double, dMu: Double) {
        self.sigmaAlphaDeg = sigmaAlphaDeg
        self.sigmaD = sigmaD
        self.dMu = dMu
    }

    /// With the full distance that puts three in four shots under `d75` yards, which is how
    /// Broadie reports drives.
    init(sigmaAlphaDeg: Double, sigmaD: Double, d75: Double) {
        let error = DispersionModel.distanceError(chance: 0.75, sigmaD: sigmaD)
        self.init(sigmaAlphaDeg: sigmaAlphaDeg, sigmaD: sigmaD, dMu: d75 / (1 + sigmaD * error))
    }

    /// The driver's pattern. `missAngle` is the player's skill: their driver angle spread, in
    /// degrees, as `MissAngle` gives it.
    static func forDriver(missAngle: Double, yards: Double, lie: Lie = .fairway) -> DispersionParams {
        DispersionParams(sigmaAlphaDeg: missAngle,
                         sigmaD: bySkill(DispersionConstants.driverDistanceSpreads, missAngle) * spread(from: lie),
                         dMu: yards)
    }

    /// Any other full shot's pattern.
    static func forApproach(missAngle: Double, yards: Double, lie: Lie = .fairway) -> DispersionParams {
        DispersionParams(sigmaAlphaDeg: bySkill(DispersionConstants.approachAngles, missAngle),
                         sigmaD: bySkill(DispersionConstants.approachDistanceSpreads, missAngle) * spread(from: lie),
                         dMu: yards)
    }

    /// A short shot's pattern: under `DispersionConstants.shortYards`.
    static func forShort(missAngle: Double, yards: Double, lie: Lie = .fairway) -> DispersionParams {
        DispersionParams(sigmaAlphaDeg: bySkill(DispersionConstants.shortAngles, missAngle),
                         sigmaD: bySkill(DispersionConstants.shortDistanceSpreads, missAngle) * spread(from: lie),
                         dMu: yards)
    }

    /// The pattern of a club that goes `yards`, hit from `lie`.
    static func forClub(isDriver: Bool, yards: Double, missAngle: Double, lie: Lie) -> DispersionParams {
        if isDriver { return forDriver(missAngle: missAngle, yards: yards, lie: lie) }
        if yards < DispersionConstants.shortYards { return forShort(missAngle: missAngle, yards: yards, lie: lie) }
        return forApproach(missAngle: missAngle, yards: yards, lie: lie)
    }

    /// What the distance spread is multiplied by for a shot from `lie`.
    static func spread(from lie: Lie) -> Double {
        switch lie {
        case .rough, .water: DispersionConstants.roughSpread
        case .sand: DispersionConstants.sandSpread
        case .fairway, .green: 1
        }
    }

    /// The value of `values`, one for each skill group, at `missAngle`: a straight line between
    /// groups, and the end group's value past the ends.
    static func bySkill(_ values: [Double], _ missAngle: Double) -> Double {
        let angles = DispersionConstants.skillAngles
        guard missAngle > angles[0] else { return values[0] }
        for index in 1..<angles.count where missAngle <= angles[index] {
            let share = (missAngle - angles[index - 1]) / (angles[index] - angles[index - 1])
            return values[index - 1] + share * (values[index] - values[index - 1])
        }
        return values[values.count - 1]
    }
}

/// The shot model of Broadie and Ko (2009). Each shot has a direction error `alpha`, a bell curve
/// around the aim with spread `sigmaAlpha`, and a standardized distance error `X` that does not
/// depend on it:
///
///     l = dMu * (1 + sigmaD * X)     the shot's length
///     x = l * sin(alpha)             right of the aim line
///     y = l * cos(alpha)             along the aim line
///
/// `X` is a mix of good shots, Normal(0.25, 0.55) with chance 0.85, and bad ones,
/// Normal(−1.6, 1.0). The mix is standardized to mean 0 and spread 1, moved by −0.15, and kept
/// at or above −0.8 / sigmaD, so that no shot is shorter than 20% of `dMu`. Mishits give it a
/// long tail of short shots, so the pattern is a teardrop. Points are in shot-local yards: the
/// ball at the origin, +y along the aim, +x right of it.
enum DispersionModel {
    /// The mean and spread of the mix before it is standardized: Σp·μ, and Σp·(σ² + μ²) − mean².
    private static let rawMean = DispersionConstants.goodShare * DispersionConstants.goodMean
        + (1 - DispersionConstants.goodShare) * DispersionConstants.badMean
    private static let rawSpread: Double = {
        let c = DispersionConstants.self
        let squares = c.goodShare * (c.goodSpread * c.goodSpread + c.goodMean * c.goodMean)
            + (1 - c.goodShare) * (c.badSpread * c.badSpread + c.badMean * c.badMean)
        return (squares - rawMean * rawMean).squareRoot()
    }()

    /// The lowest the distance error goes.
    static func lowestError(sigmaD: Double) -> Double {
        -(1 - DispersionConstants.shortestShare) / sigmaD
    }

    private static func error(raw: Double, sigmaD: Double) -> Double {
        max((raw - rawMean) / rawSpread + DispersionConstants.errorMean, lowestError(sigmaD: sigmaD))
    }

    /// The distance error with chance `chance` of a shot being under it, found by halving on the
    /// mix's own curve.
    static func distanceError(chance: Double, sigmaD: Double) -> Double {
        let c = DispersionConstants.self
        func under(_ raw: Double) -> Double {
            c.goodShare * BellCurve.chance(under: (raw - c.goodMean) / c.goodSpread)
                + (1 - c.goodShare) * BellCurve.chance(under: (raw - c.badMean) / c.badSpread)
        }
        var (low, high) = (-12.0, 8.0)
        for _ in 0..<60 {
            let middle = (low + high) / 2
            if under(middle) < chance { low = middle } else { high = middle }
        }
        return error(raw: (low + high) / 2, sigmaD: sigmaD)
    }

    /// `n` shots, in shot-local yards. The same `seed` gives the same shots.
    static func sample(_ params: DispersionParams, n: Int, seed: UInt64) -> [SIMD2<Double>] {
        let c = DispersionConstants.self
        var random = SeededRandom(seed: seed)
        let sigmaAlpha = params.sigmaAlphaDeg * .pi / 180
        var shots: [SIMD2<Double>] = []
        shots.reserveCapacity(n)
        for _ in 0..<n {
            let isGood = random.uniform() < c.goodShare
            let bell = random.normal()
            let raw = isGood ? c.goodMean + c.goodSpread * bell : c.badMean + c.badSpread * bell
            let alpha = sigmaAlpha * random.normal()
            let length = params.dMu * (1 + params.sigmaD * error(raw: raw, sigmaD: params.sigmaD))
            shots.append(SIMD2(length * sin(alpha), length * cos(alpha)))
        }
        return shots
    }

    /// Distances and angles are each split into this many steps of equal chance, so the spots are
    /// this many squared, each of equal chance.
    static let steps = 11
    /// The chances at the middle of each step: (i − 0.5) / steps.
    private static let chances = (1...steps).map { (Double($0) - 0.5) / Double(steps) }
    private static let standardSteps = chances.map(BellCurve.inverse)

    /// The pattern as spots of equal chance, for scoring it: each of `distances`, in yards and
    /// shortest first, at each of `angles`, in radians off the aim, right positive and leftmost
    /// first. No random numbers.
    static func spots(_ params: DispersionParams) -> (distances: [Double], angles: [Double]) {
        let sigmaAlpha = params.sigmaAlphaDeg * .pi / 180
        return (chances.map { params.dMu * (1 + params.sigmaD * distanceError(chance: $0, sigmaD: params.sigmaD)) },
                standardSteps.map { $0 * sigmaAlpha })
    }
}

/// The standard bell curve: mean 0, standard deviation 1.
enum BellCurve {
    /// The chance of a value under `z`.
    static func chance(under z: Double) -> Double {
        0.5 * erfc(-z / 2.0.squareRoot())
    }

    /// The value with chance `p` of being under it, by Acklam's approximation (good to about
    /// 1 part in a billion). `p` is kept inside 0 and 1.
    static func inverse(_ p: Double) -> Double {
        let (a, b, c, d) = (Self.a, Self.b, Self.c, Self.d)
        let p = min(max(p, 1e-12), 1 - 1e-12)
        let low = 0.02425
        func tail(_ q: Double) -> Double {
            (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        if p < low {
            return tail((-2 * log(p)).squareRoot())
        }
        if p > 1 - low {
            return -tail((-2 * log(1 - p)).squareRoot())
        }
        let q = p - 0.5
        let r = q * q
        return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
            / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
    }

    private static let a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
                            1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
    private static let b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
                            6.680131188771972e+01, -1.328068155288572e+01]
    private static let c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
                            -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
    private static let d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
                            3.754408661907416e+00]
}
