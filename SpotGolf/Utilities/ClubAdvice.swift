import CoreLocation
import CourseDataSwift

/// The club and aim with the lowest expected score from where the player stands: each club's
/// pattern is tried at aims up to 45° either side of the line to the pin, and its spots scored by
/// the strokes to hole out from where they stop. See plans/2026-11-02-caddie-club-and-aim.md,
/// section 3.
struct ClubAdvice {
    /// How far either side of the line to the pin the aims go, in whole degrees.
    static let maxAimOffset = 45
    /// Each club's aims are tried this many degrees apart, then at each whole degree within
    /// `fineSpan` of its best.
    static let coarseStep = 3
    static let fineSpan = 2
    /// Expected scores this close are a tie, which goes to the aim nearer the line to the pin.
    static let tieMargin = 0.005

    let club: Club
    /// The club's Caddie average: the yards to the aim point.
    let yards: Int
    let pattern: ShotPattern
    /// The shot itself plus the average strokes to hole out from its spots.
    let expectedStrokes: Double
    /// Whole degrees right (+) or left (−) of the line to the pin.
    let aimOffset: Int
    let plane: GroundPlane

    /// The shot as the map draws it.
    var shot: CaddieShot {
        CaddieShot(club: club, yards: yards, pattern: pattern, plane: plane)
    }

    var startCoordinate: CLLocationCoordinate2D { shot.startCoordinate }
    var aimCoordinate: CLLocationCoordinate2D { shot.aimCoordinate }

    func corners(k: Double) -> [CLLocationCoordinate2D] {
        shot.corners(k: k)
    }

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

    /// The best of `clubs` from `start`, with `missAngle` in degrees. Nil without clubs, or when
    /// the task it runs in is cancelled.
    static func best(from start: GroundPoint, pin: GroundPoint, clubs: [(club: Club, distance: ClubDistance)],
                     missAngle: Double, lies: LieGrid) -> ClubAdvice? {
        let toPin = start.heading(to: pin)
        // Nearest the line to the pin first, so a near tie keeps the aim nearer it
        let coarse = [0] + stride(from: coarseStep, through: maxAimOffset, by: coarseStep).flatMap { [-$0, $0] }
        var best: ClubAdvice?
        for (club, distance) in clubs {
            if Task.isCancelled { return nil }
            var clubBest: ClubAdvice?
            func consider(_ offset: Int) {
                // Right of the line is clockwise
                let pattern = ShotPattern(start: start, heading: toPin - Double(offset) * .pi / 180,
                                          distance: distance, missAngle: missAngle)
                let strokes = expectedStrokes(of: pattern, pin: pin, lies: lies)
                if let current = clubBest, !isBetter(strokes, offset: offset, than: current) { return }
                clubBest = ClubAdvice(club: club, yards: distance.average, pattern: pattern, expectedStrokes: strokes,
                                      aimOffset: offset, plane: lies.plane)
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

    /// 1 for the shot, plus the average over the pattern's spots of the strokes to hole out.
    static func expectedStrokes(of pattern: ShotPattern, pin: GroundPoint, lies: LieGrid) -> Double {
        // The spots of `pattern.spots`, made here rather than as an array: this runs tens of
        // thousands of times a pick
        var total = 0.0
        for angle in pattern.angles {
            let direction = pattern.heading - angle
            let (east, north) = (cos(direction), sin(direction))
            for distance in pattern.distances {
                let spot = GroundPoint(x: pattern.start.x + distance * east, y: pattern.start.y + distance * north)
                total += strokesToHoleOut(from: spot, start: pattern.start, pin: pin, lies: lies)
            }
        }
        return 1 + total / Double(pattern.angles.count * pattern.distances.count)
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

/// A club's shot pattern from where the player stands, as the map draws it: the Caddie's pick, or
/// the aim the player dragged it to. See plans/2026-11-02-caddie-club-and-aim.md, section 1.
struct CaddieShot {
    let club: Club
    /// The club's Caddie average: the yards to the aim point.
    let yards: Int
    let pattern: ShotPattern
    let plane: GroundPlane

    var startCoordinate: CLLocationCoordinate2D { plane.coordinate(pattern.start) }
    var aimCoordinate: CLLocationCoordinate2D { plane.coordinate(pattern.aimPoint) }

    /// The trapezoid `k` standard deviations out, as `ShotPattern.corners(k:)` gives it.
    func corners(k: Double) -> [CLLocationCoordinate2D] {
        pattern.corners(k: k).map(plane.coordinate)
    }

    /// From `location` straight at `target`, with the club of `clubs` whose average is nearest
    /// the yards to it, a tie going to the longer club. `missAngle` is in degrees. Nil without
    /// clubs.
    static func aimed(at target: CLLocationCoordinate2D, from location: CLLocationCoordinate2D,
                      clubs: [(club: Club, distance: ClubDistance)], missAngle: Double) -> CaddieShot? {
        let plane = GroundPlane(origin: Coordinate(lat: location.latitude, lon: location.longitude))
        let start = GroundPoint(x: 0, y: 0)
        let aim = plane.point(target)
        let yards = start.distance(to: aim) / 0.9144
        let nearest = clubs.min { a, b in
            let gapA = abs(Double(a.distance.average) - yards), gapB = abs(Double(b.distance.average) - yards)
            return gapA != gapB ? gapA < gapB : a.distance.average > b.distance.average
        }
        guard let (club, distance) = nearest else { return nil }
        return CaddieShot(club: club, yards: distance.average,
                          pattern: ShotPattern(start: start, heading: start.heading(to: aim), distance: distance,
                                               missAngle: missAngle),
                          plane: plane)
    }
}

/// Works out the Caddie's advice off the main thread, keeping the lie grid between requests on
/// one hole.
actor ClubAdviser {
    private var lies: LieGrid?
    private var liesHole: ClubAdvice.HoleKey?

    func advice(for request: ClubAdvice.Request) -> ClubAdvice? {
        if request.hole != liesHole {
            lies = LieGrid(course: request.course, hole: request.courseHole, plane: GroundPlane(origin: request.greenCenter))
            liesHole = request.hole
        }
        guard let lies else { return nil }
        return ClubAdvice.best(from: lies.plane.point(request.start), pin: lies.plane.point(request.pin),
                               clubs: request.clubs, missAngle: request.missAngle, lies: lies)
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
