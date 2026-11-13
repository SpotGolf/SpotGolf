import CoreLocation
import CourseDataSwift
import simd

/// The club and aim with the lowest expected score from where the player stands: each club's
/// pattern is tried at aims up to 45° either side of the line to the pin, and its spots scored by
/// the strokes to hole out from where they stop. Only aims whose aim point is on the hole's
/// fairway or green count; when none is, aims within 20 yards of the centerline. See
/// plans/2026-11-02-caddie-club-and-aim.md, section 3, and plans/2026-11-11-shot-dispersion.md
/// for the pattern.
struct ClubAdvice {
    /// How far either side of the line to the pin the aims go, in whole degrees.
    static let maxAimOffset = 45
    /// Each club's aims are tried this many degrees apart, then at each whole degree within
    /// `fineSpan` of its best.
    static let coarseStep = 3
    static let fineSpan = 2
    /// Expected scores this close are a tie, which goes to the aim nearer the line to the pin.
    static let tieMargin = 0.005
    /// When no aim point is on the fairway or green, aim points this far either side of the
    /// centerline count: 20 yards, in meters.
    static let centerlineHalfWidth = 20 * 0.9144

    /// Which aim points count, tried in order until one gives advice.
    enum AimRule: CaseIterable {
        /// On the hole's fairway or green.
        case landing
        /// Within `centerlineHalfWidth` of the hole's centerline.
        case centerline
        /// Any, for a hole with neither, or a player too far off the hole for the others.
        case any

        func allows(_ point: GroundPoint, lies: LieGrid) -> Bool {
            switch self {
            case .landing: lies.isLanding(point)
            case .centerline: lies.isNearCenterline(point, within: ClubAdvice.centerlineHalfWidth)
            case .any: true
            }
        }
    }

    let club: Club
    /// The club's Caddie average: the yards to the aim point.
    let yards: Int
    /// The shot as the map draws it.
    var shot: CaddieShot
    /// The shot itself plus the average strokes to hole out from its spots.
    let expectedStrokes: Double
    /// Whole degrees right (+) or left (−) of the line to the pin.
    let aimOffset: Int
    /// Where the player stands, which sets how much the distance spreads.
    let startLie: Lie
    /// The shape of each club the player can hit from here, for when they drag the aim. Filled
    /// in by `ClubAdviser`, with the shot's own shape.
    var shapes: [Club: DispersionShape] = [:]
    /// The chance of the shot stopping on each lie. Filled in by `ClubAdviser`.
    var outcomes: DispersionOutcomes?
    /// The water and sand shapes any club could reach, which the map marks inside the pattern.
    /// Filled in by `ClubAdviser`.
    var hazards: [[CLLocationCoordinate2D]] = []
    /// A shot reaches no farther than this, in meters.
    static let reach = 400.0

    var startCoordinate: CLLocationCoordinate2D { shot.startCoordinate }
    var aimCoordinate: CLLocationCoordinate2D { shot.aimCoordinate }

    /// The clubs the player can hit from here: never the putter, and the driver only for a tee
    /// shot.
    static func clubs(from distances: [(club: Club, distance: ClubDistance)],
                      isTeeShot: Bool) -> [(club: Club, distance: ClubDistance)] {
        distances.filter { $0.club.kind != .putter && (isTeeShot || $0.club.id != "dr") }
    }

    /// What to work out for the player at `location` on hole `holeIndex`. Nil when the map shows
    /// no advice: outside an active round, on a hole other than the display hole, on a hole
    /// without a green, on the green or within `greenZone` meters of its edge, or with no club to
    /// hit. The driver is only for a tee shot, while the hole has no strokes yet.
    static func request(at location: CLLocationCoordinate2D, round: Round, holeIndex: Int,
                        distances: [(club: Club, distance: ClubDistance)], missAngle: Double,
                        greenZone: CLLocationDistance) -> Request? {
        guard round.isActive, holeIndex == round.displayHoleIndex,
              let hole = round.courseHole(at: holeIndex), let green = round.green(holeIndex: holeIndex),
              let pin = round.targetCoordinate(holeIndex: holeIndex) else { return nil }
        let start = Coordinate(lat: location.latitude, lon: location.longitude)
        guard HoleShape.distance(from: start, to: Array(green.polygon)) > greenZone else { return nil }
        let hittable = clubs(from: distances, isTeeShot: round.hole(at: holeIndex).strokes.isEmpty)
        guard !hittable.isEmpty else { return nil }
        return Request(hole: HoleKey(roundID: round.id, holeIndex: holeIndex), course: round.course,
                       courseHole: hole, greenCenter: green.center, start: start,
                       pin: Coordinate(lat: pin.latitude, lon: pin.longitude), clubs: hittable, missAngle: missAngle)
    }

    /// One hole of one round.
    struct HoleKey: Equatable, Sendable {
        var roundID: UUID
        var holeIndex: Int
    }

    /// Everything the advice is worked out from, so it can be worked out off the main thread.
    struct Request: Sendable {
        var hole: HoleKey
        var course: Course
        var courseHole: Hole
        /// Where the hole's lie grid is flattened around.
        var greenCenter: Coordinate
        var start: Coordinate
        var pin: Coordinate
        var clubs: [(club: Club, distance: ClubDistance)]
        /// In degrees.
        var missAngle: Double
        /// Set by `ClubAdviceState`, so an answer to an older request is dropped.
        var generation = 0
    }

    /// The best of `clubs` from `start`, with `missAngle` the player's skill, as `MissAngle`
    /// gives it. Nil without clubs, or when the task it runs in is cancelled.
    static func best(from start: GroundPoint, pin: GroundPoint, clubs: [(club: Club, distance: ClubDistance)],
                     missAngle: Double, lies: LieGrid) -> ClubAdvice? {
        for rule in AimRule.allCases {
            if Task.isCancelled { return nil }
            if let advice = best(from: start, pin: pin, clubs: clubs, missAngle: missAngle, lies: lies, rule: rule) {
                return advice
            }
        }
        return nil
    }

    /// The best of `clubs` whose aim point `rule` allows. Nil when it allows none.
    static func best(from start: GroundPoint, pin: GroundPoint, clubs: [(club: Club, distance: ClubDistance)],
                     missAngle: Double, lies: LieGrid, rule: AimRule) -> ClubAdvice? {
        let toPin = start.heading(to: pin)
        let lie = lies.lie(at: start)
        // Nearest the line to the pin first, so a near tie keeps the aim nearer it
        let coarse = [0] + stride(from: coarseStep, through: maxAimOffset, by: coarseStep).flatMap { [-$0, $0] }
        var best: ClubAdvice?
        for (club, distance) in clubs {
            if Task.isCancelled { return nil }
            let params = CaddieShot.params(club, distance: distance, missAngle: missAngle, lie: lie)
            let straight = ShotSpots(params, start: start, heading: toPin)
            var clubBest: ClubAdvice?
            func consider(_ offset: Int) {
                // Right of the line is clockwise
                let heading = toPin - Double(offset) * .pi / 180
                guard rule.allows(start.moved(Double(distance.average) * 0.9144, heading: heading), lies: lies) else { return }
                let spots = straight.turned(to: heading)
                let strokes = expectedStrokes(of: spots, pin: pin, lies: lies)
                if let current = clubBest, !isBetter(strokes, offset: offset, than: current) { return }
                clubBest = ClubAdvice(club: club, yards: distance.average,
                                      shot: CaddieShot(club: club, yards: distance.average, params: params, spots: spots,
                                                       plane: lies.plane),
                                      expectedStrokes: strokes, aimOffset: offset, startLie: lie)
            }
            coarse.forEach(consider)
            if let center = clubBest?.aimOffset {
                (1...fineSpan).flatMap { [center - $0, center + $0] }
                    .filter { abs($0) <= maxAimOffset }
                    .sorted { abs($0) < abs($1) }
                    .forEach(consider)
            }
            if let clubBest, best.map({ isBetter(clubBest.expectedStrokes, offset: clubBest.aimOffset, than: $0) }) ?? true {
                best = clubBest
            }
        }
        return best
    }

    /// 1 for the shot, plus the average over its spots of the strokes to hole out.
    static func expectedStrokes(of spots: ShotSpots, pin: GroundPoint, lies: LieGrid) -> Double {
        // The spots of `spots.points`, made here rather than as an array: this runs tens of
        // thousands of times a pick
        var total = 0.0
        for angle in spots.angles {
            let direction = spots.heading - angle
            let (east, north) = (cos(direction), sin(direction))
            for distance in spots.distances {
                let spot = GroundPoint(x: spots.start.x + distance * east, y: spots.start.y + distance * north)
                total += strokesToHoleOut(from: spot, start: spots.start, pin: pin, lies: lies)
            }
        }
        return 1 + total / Double(spots.angles.count * spots.distances.count)
    }

    /// A ball in water is dropped where it last went in, with a penalty stroke.
    static func strokesToHoleOut(from spot: GroundPoint, start: GroundPoint, pin: GroundPoint, lies: LieGrid) -> Double {
        let lie = lies.lie(at: spot)
        let from = lie == .water ? lies.waterEntry(from: start, to: spot) : spot
        return StrokesToHoleOut.strokes(lie, yards: from.distance(to: pin) / 0.9144)
    }

    private static func isBetter(_ strokes: Double, offset: Int, than current: ClubAdvice) -> Bool {
        if strokes < current.expectedStrokes - tieMargin { return true }
        return strokes <= current.expectedStrokes + tieMargin && abs(offset) < abs(current.aimOffset)
    }
}

/// A shot's pattern as spots of equal chance, for scoring it: each distance at each angle, as
/// `DispersionModel.spots` gives them. See plans/2026-11-11-shot-dispersion.md, section 4.
struct ShotSpots {
    let start: GroundPoint
    /// The aim, in radians counter-clockwise from east.
    let heading: Double
    /// In meters, shortest first.
    let distances: [Double]
    /// Off the aim, in radians, right positive, leftmost first.
    let angles: [Double]

    init(_ params: DispersionParams, start: GroundPoint, heading: Double) {
        let spots = DispersionModel.spots(params)
        self.init(start: start, heading: heading, distances: spots.distances.map { $0 * 0.9144 }, angles: spots.angles)
    }

    private init(start: GroundPoint, heading: Double, distances: [Double], angles: [Double]) {
        self.start = start
        self.heading = heading
        self.distances = distances
        self.angles = angles
    }

    /// The same spots along another aim.
    func turned(to heading: Double) -> ShotSpots {
        ShotSpots(start: start, heading: heading, distances: distances, angles: angles)
    }

    var points: [GroundPoint] {
        angles.flatMap { angle in
            // Right of the aim is clockwise
            distances.map { start.moved($0, heading: heading - angle) }
        }
    }
}

/// A club's shot pattern from where the player stands, as the map draws it: the Caddie's pick, or
/// the aim the player dragged it to. See plans/2026-11-11-shot-dispersion.md, section 6.
struct CaddieShot {
    let club: Club
    /// The club's Caddie average: the yards to the aim point.
    let yards: Int
    let params: DispersionParams
    let spots: ShotSpots
    let plane: GroundPlane
    /// The regions the map draws. Nil until it is worked out.
    var shape: DispersionShape?

    var start: GroundPoint { spots.start }
    var heading: Double { spots.heading }
    /// Where the club's average distance lands along the aim.
    var aimPoint: GroundPoint { start.moved(Double(yards) * 0.9144, heading: heading) }
    var startCoordinate: CLLocationCoordinate2D { plane.coordinate(start) }
    var aimCoordinate: CLLocationCoordinate2D { plane.coordinate(aimPoint) }

    /// A point of the shape, in shot-local yards, on the ground.
    func groundPoint(_ local: SIMD2<Double>) -> GroundPoint {
        let meters = 0.9144
        let along = GroundPoint(x: cos(heading), y: sin(heading))
        let right = GroundPoint(x: sin(heading), y: -cos(heading))
        return start + along * (local.y * meters) + right * (local.x * meters)
    }

    /// A region's outline on the map.
    func outline(_ region: DispersionShape.Region) -> [CLLocationCoordinate2D] {
        region.ring.map { plane.coordinate(groundPoint($0)) }
    }

    /// The pattern of `club` hit from `lie`, with `missAngle` the player's skill.
    static func params(_ club: Club, distance: ClubDistance, missAngle: Double, lie: Lie) -> DispersionParams {
        DispersionParams.forClub(isDriver: club.id == "dr", yards: Double(distance.average), missAngle: missAngle, lie: lie)
    }

    /// From `location` straight at `target`, with the club of `clubs` whose average is nearest
    /// the yards to it, a tie going to the longer club. `missAngle` is the player's skill, `lie`
    /// where they stand, and `shapes` each club's shape from there. Nil without clubs.
    static func aimed(at target: CLLocationCoordinate2D, from location: CLLocationCoordinate2D,
                      clubs: [(club: Club, distance: ClubDistance)], missAngle: Double, lie: Lie = .fairway,
                      shapes: [Club: DispersionShape] = [:]) -> CaddieShot? {
        let plane = GroundPlane(origin: Coordinate(lat: location.latitude, lon: location.longitude))
        let start = GroundPoint(x: 0, y: 0)
        let aim = plane.point(target)
        let yards = start.distance(to: aim) / 0.9144
        let nearest = clubs.min { a, b in
            let gapA = abs(Double(a.distance.average) - yards), gapB = abs(Double(b.distance.average) - yards)
            return gapA != gapB ? gapA < gapB : a.distance.average > b.distance.average
        }
        guard let (club, distance) = nearest else { return nil }
        let params = params(club, distance: distance, missAngle: missAngle, lie: lie)
        return CaddieShot(club: club, yards: distance.average, params: params,
                          spots: ShotSpots(params, start: start, heading: start.heading(to: aim)), plane: plane,
                          shape: shapes[club])
    }
}

/// Works out the Caddie's advice off the main thread, keeping the lie grid between requests on
/// one hole, and each pattern's shape once it is worked out.
actor ClubAdviser {
    private var lies: LieGrid?
    private var liesHole: ClubAdvice.HoleKey?
    /// The shots of the last few pairs of spreads, at a full distance of 1.
    private var shots: [SpreadKey: DispersionShots] = [:]
    private var shapes: [SpreadKey: DispersionShape] = [:]

    /// The angle spread to 0.1°, and the distance spread to 0.005.
    private struct SpreadKey: Hashable {
        let angle: Int
        let distance: Int

        init(_ params: DispersionParams) {
            angle = Int((params.sigmaAlphaDeg * 10).rounded())
            distance = Int((params.sigmaD * 200).rounded())
        }

        var sigmaAlphaDeg: Double { Double(angle) / 10 }
        var sigmaD: Double { Double(distance) / 200 }
    }

    func advice(for request: ClubAdvice.Request) -> ClubAdvice? {
        if request.hole != liesHole {
            lies = LieGrid(course: request.course, hole: request.courseHole, plane: GroundPlane(origin: request.greenCenter))
            liesHole = request.hole
        }
        guard let lies,
              var advice = ClubAdvice.best(from: lies.plane.point(request.start), pin: lies.plane.point(request.pin),
                                           clubs: request.clubs, missAngle: request.missAngle, lies: lies) else { return nil }
        for (club, distance) in request.clubs {
            if Task.isCancelled { return nil }
            advice.shapes[club] = shape(of: CaddieShot.params(club, distance: distance, missAngle: request.missAngle,
                                                              lie: advice.startLie))
        }
        advice.shot.shape = advice.shapes[advice.club]
        advice.hazards = lies.hazards(near: advice.shot.start, reach: ClubAdvice.reach).map { $0.map(lies.plane.coordinate) }
        advice.outcomes = DispersionOutcomes(shots: outcomeShots(advice.shot.params), start: advice.shot.start,
                                             heading: advice.shot.heading, lies: lies)
        return advice
    }

    /// The chance of `shot`, one the player aimed themself on `hole`, stopping on each lie. Nil
    /// when the hole is not the one the last advice was for.
    func outcomes(of shot: CaddieShot, hole: ClubAdvice.HoleKey) -> DispersionOutcomes? {
        guard hole == liesHole, let lies else { return nil }
        // The shot is on its own plane, around the player
        let start = lies.plane.point(shot.startCoordinate)
        let aim = lies.plane.point(shot.aimCoordinate)
        return DispersionOutcomes(shots: outcomeShots(shot.params), start: start, heading: start.heading(to: aim), lies: lies)
    }

    /// The pattern's shape. It is kept by its spreads, at a full distance of 1: a pattern grows
    /// evenly with its full distance.
    func shape(of params: DispersionParams) -> DispersionShape {
        let key = SpreadKey(params)
        let kept: DispersionShape
        if let shape = shapes[key] {
            kept = shape
        } else {
            kept = DispersionContours.shape(of: unitShots(key), dMu: 1)
            shapes[key] = kept
        }
        return kept.scaled(by: params.dMu)
    }

    private func outcomeShots(_ params: DispersionParams) -> [SIMD2<Double>] {
        unitShots(SpreadKey(params)).shots.prefix(DispersionConstants.outcomeShots).map { $0 * params.dMu }
    }

    private func unitShots(_ key: SpreadKey) -> DispersionShots {
        if let kept = shots[key] { return kept }
        // A few megabytes each: the driver's and the other clubs', from a lie or two
        if shots.count >= 6 {
            shots.removeAll()
        }
        let made = DispersionShots(sigmaAlphaDeg: key.sigmaAlphaDeg, sigmaD: key.sigmaD)
        shots[key] = made
        return made
    }
}

/// The map's Caddie advice, worked out again only when what it comes from changes or the player
/// moves 3 yards. See plans/2026-11-02-caddie-club-and-aim.md, section 4.
struct ClubAdviceState {
    /// Moves shorter than this keep the advice: 3 yards, in meters.
    static let moveThreshold = 3 * 0.9144

    /// Everything but the player's location that the advice comes from.
    struct Inputs: Equatable {
        var roundID: UUID
        var holeIndex: Int
        var displayHoleIndex: Int
        var isActive: Bool
        var pin: Coordinate?
        /// The hole's strokes: the driver is only for a tee shot.
        var holeStrokes: Int
        var clubs: [Club]
        var distances: [ClubDistance]
        var missAngle: Double
        var greenZone: Double

        init(round: Round, holeIndex: Int, distances: [(club: Club, distance: ClubDistance)], missAngle: Double,
             greenZone: CLLocationDistance) {
            roundID = round.id
            self.holeIndex = holeIndex
            displayHoleIndex = round.displayHoleIndex
            isActive = round.isActive
            pin = round.targetCoordinate(holeIndex: holeIndex).map { Coordinate(lat: $0.latitude, lon: $0.longitude) }
            holeStrokes = round.hole(at: holeIndex).strokes.count
            clubs = distances.map(\.club)
            self.distances = distances.map(\.distance)
            self.missAngle = missAngle
            self.greenZone = greenZone
        }
    }

    private(set) var advice: ClubAdvice?
    private var inputs: Inputs?
    private var location: CLLocationCoordinate2D?
    private var generation = 0

    /// The request to work out when `inputs` changed or the player moved 3 yards since the last
    /// time, for `ClubAdviser`; hand its answer to `finish`. Nil when the advice stays as it is,
    /// or when there is none to show, which clears it.
    mutating func update(_ inputs: Inputs, round: Round, location: CLLocationCoordinate2D?) -> ClubAdvice.Request? {
        guard let location else {
            clear()
            return nil
        }
        if inputs == self.inputs, let last = self.location,
           LocalDistance.meters(fromLat: last.latitude, lon: last.longitude,
                                toLat: location.latitude, lon: location.longitude) < Self.moveThreshold {
            return nil
        }
        self.inputs = inputs
        self.location = location
        generation += 1
        guard var request = ClubAdvice.request(at: location, round: round, holeIndex: inputs.holeIndex,
                                               distances: Array(zip(inputs.clubs, inputs.distances)).map { (club: $0, distance: $1) },
                                               missAngle: inputs.missAngle, greenZone: inputs.greenZone) else {
            advice = nil
            return nil
        }
        request.generation = generation
        return request
    }

    /// Shows the answer to a request from `update`, unless a newer one has been made since. The
    /// old advice shows until then.
    mutating func finish(_ advice: ClubAdvice?, generation: Int) {
        guard generation == self.generation else { return }
        self.advice = advice
    }

    /// No advice until the next update, which then always makes a request.
    mutating func clear() {
        advice = nil
        inputs = nil
        location = nil
        generation += 1
    }
}
