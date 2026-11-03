import Foundation

/// Where one club's shots from a start along an aim are likely to stop: a split bell curve of
/// distance, with the Caddie's short and long spreads, and a bell curve of miss angle. See
/// plans/2026-11-02-caddie-club-and-aim.md, section 2.
struct ShotPattern {
    /// Distances and angles are each split into this many steps of equal chance, so the pattern
    /// is this many squared spots of equal chance.
    static let steps = 11

    let start: GroundPoint
    /// The aim, in radians counter-clockwise from east.
    let heading: Double
    /// In meters.
    let average: Double
    let shortSpread: Double
    let longSpread: Double
    /// The miss angle's standard deviation, in radians.
    let missAngle: Double

    /// The distances of the spots, in meters, shortest first.
    let distances: [Double]
    /// The angles of the spots off the aim, in radians, right positive, leftmost first.
    let angles: [Double]

    /// `missAngle` is in degrees.
    init(start: GroundPoint, heading: Double, distance: ClubDistance, missAngle: Double) {
        let meters = 0.9144
        self.init(start: start, heading: heading, average: Double(distance.average) * meters,
                  shortSpread: Double(distance.average - distance.low) * meters,
                  longSpread: Double(distance.high - distance.average) * meters,
                  missAngle: missAngle * .pi / 180)
    }

    /// In meters and radians.
    init(start: GroundPoint, heading: Double, average: Double, shortSpread: Double, longSpread: Double,
         missAngle: Double) {
        self.start = start
        self.heading = heading
        self.average = average
        self.shortSpread = shortSpread
        self.longSpread = longSpread
        self.missAngle = missAngle
        distances = Self.chances.map {
            max(0, Self.splitBellCurve($0, peak: average, below: shortSpread, above: longSpread))
        }
        angles = Self.standardSteps.map { $0 * missAngle }
    }

    /// Where the average distance lands along the aim.
    var aimPoint: GroundPoint { start.moved(average, heading: heading) }

    /// The spots of equal chance, each distance at each angle.
    var spots: [GroundPoint] {
        angles.flatMap { angle in
            // Right of the aim is clockwise
            let direction = heading - angle
            return distances.map { start.moved($0, heading: direction) }
        }
    }

    /// The trapezoid `k` standard deviations out each way: near left, near right, far right, far
    /// left. The near and far edges are square to the aim.
    func corners(k: Double) -> [GroundPoint] {
        let near = max(0, average - k * shortSpread)
        let far = average + k * longSpread
        let spread = tan(k * missAngle)
        let along = GroundPoint(x: cos(heading), y: sin(heading))
        let right = GroundPoint(x: sin(heading), y: -cos(heading))
        func corner(_ distance: Double, side: Double) -> GroundPoint {
            start + along * distance + right * (side * distance * spread)
        }
        return [corner(near, side: -1), corner(near, side: 1), corner(far, side: 1), corner(far, side: -1)]
    }

    /// The chances at the middle of each step: (i − 0.5) / steps.
    private static let chances = (1...steps).map { (Double($0) - 0.5) / Double(steps) }
    /// The standard bell curve at each chance.
    private static let standardSteps = chances.map(BellCurve.inverse)

    /// The value with chance `p` of being under it, on a bell curve with its peak at `peak`,
    /// spread `below` under it and `above` over it.
    static func splitBellCurve(_ p: Double, peak: Double, below: Double, above: Double) -> Double {
        let total = below + above
        guard total > 0 else { return peak }
        let underPeak = below / total
        if p < underPeak {
            return peak + below * BellCurve.inverse(p * total / (2 * below))
        }
        return peak + above * BellCurve.inverse(0.5 + (p - underPeak) * total / (2 * above))
    }
}

/// The standard bell curve: mean 0, standard deviation 1.
enum BellCurve {
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
