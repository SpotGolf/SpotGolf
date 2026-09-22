import Foundation
import CoreLocation
import CourseDataSwift

/// Repeatable random numbers, so a simulated round is the same on every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    // SplitMix64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension RandomNumberGenerator {
    mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &self)
    }

    mutating func chance(_ probability: Double) -> Bool {
        uniform(0...1) < probability
    }

    // Box-Muller
    mutating func gaussian(mean: Double = 0, deviation: Double) -> Double {
        let u1 = uniform(Double.leastNonzeroMagnitude...1)
        let u2 = uniform(0...1)
        return mean + deviation * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

/// Meters east (`x`) and north (`y`) of the course's origin.
struct Vec: Equatable {
    var x: Double
    var y: Double

    static func + (a: Vec, b: Vec) -> Vec { Vec(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Vec, b: Vec) -> Vec { Vec(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: Vec, k: Double) -> Vec { Vec(x: a.x * k, y: a.y * k) }

    var length: Double { (x * x + y * y).squareRoot() }
    var unit: Vec { length > 0 ? self * (1 / length) : Vec(x: 1, y: 0) }
    /// Turned 90° counter-clockwise: the left-hand side when facing along the vector.
    var left: Vec { Vec(x: -y, y: x) }

    func distance(to other: Vec) -> Double { (self - other).length }
}

/// Flat-earth conversion between coordinates and meters. Good to centimeters across one course.
struct LocalPlane {
    static let metersPerDegreeLatitude = 111_132.0

    let origin: Coordinate
    let metersPerDegreeLongitude: Double

    init(origin: Coordinate) {
        self.origin = origin
        metersPerDegreeLongitude = 111_320 * cos(origin.latitude * .pi / 180)
    }

    func point(_ coordinate: Coordinate) -> Vec {
        Vec(x: (coordinate.longitude - origin.longitude) * metersPerDegreeLongitude,
            y: (coordinate.latitude - origin.latitude) * Self.metersPerDegreeLatitude)
    }

    func coordinate(_ point: Vec) -> Coordinate {
        Coordinate(latitude: origin.latitude + point.y / Self.metersPerDegreeLatitude,
                   longitude: origin.longitude + point.x / metersPerDegreeLongitude)
    }
}

/// A water hazard in meters, with what is needed to walk around it.
struct Pond {
    let polygon: [Vec]
    /// Points about 5 meters outside the bank, used as corners when walking around.
    let bankPoints: [Vec]
    private let low: Vec
    private let high: Vec

    init(polygon: [Vec]) {
        self.polygon = polygon
        low = Vec(x: polygon.map(\.x).min() ?? 0, y: polygon.map(\.y).min() ?? 0)
        high = Vec(x: polygon.map(\.x).max() ?? 0, y: polygon.map(\.y).max() ?? 0)

        // About 24 corners per pond is plenty. Each is pushed outward along its corner's normal.
        let stride = max(1, polygon.count / 24)
        let corners = Swift.stride(from: 0, to: polygon.count, by: stride).map { polygon[$0] }
        var area = 0.0
        for (a, b) in zip(corners, corners.dropFirst() + corners.prefix(1)) {
            area += a.x * b.y - b.x * a.y
        }
        let outward: Double = area > 0 ? -1 : 1 // counter-clockwise rings have their inside on the left
        bankPoints = corners.indices.map { index in
            let before = corners[(index + corners.count - 1) % corners.count], after = corners[(index + 1) % corners.count]
            let normal = ((corners[index] - before).unit.left + (after - corners[index]).unit.left).unit * outward
            return corners[index] + normal * 5
        }
    }

    func contains(_ point: Vec) -> Bool {
        guard point.x >= low.x, point.x <= high.x, point.y >= low.y, point.y <= high.y else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// False when the line from `a` to `b` is nowhere near this pond.
    func mayTouch(_ a: Vec, _ b: Vec) -> Bool {
        max(a.x, b.x) >= low.x && min(a.x, b.x) <= high.x && max(a.y, b.y) >= low.y && min(a.y, b.y) <= high.y
    }
}

/// One swing, as ground truth for anything that later tries to find swings in a track.
struct SimulatedShot: Equatable {
    let holeNumber: Int
    let stroke: Int
    let time: Date
    let player: Coordinate // where the player stands
    let ball: Coordinate // where the ball lies before the swing
    let landing: Coordinate
}

struct SimulatedRound {
    /// What the GPS reports, one fix per second.
    let fixes: [CLLocation]
    /// Where the player really was at each fix.
    let truePath: [Coordinate]
    let shots: [SimulatedShot]
}

/// Plays holes of a real course the way a golfer in a group does, and reports the GPS fixes
/// a device on the player would record.
///
/// The player aims along each hole's centerline, misses by realistic amounts, avoids water,
/// and chips and putts out. Between swings the player walks curved, wandering paths, stops at
/// a partner's ball, lines up behind their own, reads putts, and waits on the tee and beside
/// the green. Waiting time is stretched so every hole takes exactly `secondsPerHole`.
struct RoundSimulator {
    let course: Course
    let holes: [Hole]
    let teeName: String

    private let plane: LocalPlane
    private let ponds: [Pond]
    private var random: SeededGenerator

    init(course: Course, subCourseIndex: Int, teeName: String, seed: UInt64) {
        self.course = course
        self.holes = course.subCourses[subCourseIndex].holes
        self.teeName = teeName
        let plane = LocalPlane(origin: course.location.coordinate)
        self.plane = plane
        ponds = course.features.filter { $0.type == .water }.map { Pond(polygon: $0.polygon.map(plane.point)) }
        random = SeededGenerator(seed: seed)
    }

    // MARK: - Timeline

    private enum Step {
        /// `flexible` stands are waits for other players; they stretch to fill the hole's time.
        case stand(at: Vec, seconds: Double, flexible: Bool)
        case walk(path: [Vec], speed: Double)
    }

    private struct PlannedShot {
        let stroke: Int
        let swingAfterStep: Int // the swing happens as this step ends
        let player: Vec
        let ball: Vec
        let landing: Vec
    }

    private struct HoleLayout {
        let hole: Hole
        let tee: Vec
        let centerline: [Vec]
        let pin: Vec
    }

    // MARK: - Playing

    mutating func play(holeNumbers: ClosedRange<Int>, start: Date, secondsPerHole: Int) -> SimulatedRound {
        // The hole after the last one is needed too: the player walks to its tee
        var layouts: [Int: HoleLayout] = [:]
        for hole in holes where holeNumbers.contains(hole.number) || hole.number == holeNumbers.upperBound + 1 {
            layouts[hole.number] = makeLayout(hole)
        }

        var path: [Vec] = []
        var shots: [SimulatedShot] = []
        var player: Vec?

        for number in holeNumbers {
            guard let layout = layouts[number] else { continue }
            let nextTee = layouts[number + 1].map { waitingSpot($0) }
            let holeStart = start.addingTimeInterval(Double(path.count))

            var steps: [Step] = []
            let planned = planHole(layout, from: player ?? waitingSpot(layout), nextTee: nextTee, steps: &steps)
            let durations = fit(steps, into: Double(secondsPerHole))

            path += sample(steps, durations: durations, seconds: secondsPerHole)
            player = endPoint(of: steps)

            for shot in planned {
                let seconds = durations[0...shot.swingAfterStep].reduce(0, +)
                shots.append(SimulatedShot(holeNumber: number,
                                           stroke: shot.stroke,
                                           time: holeStart.addingTimeInterval(seconds.rounded()),
                                           player: plane.coordinate(shot.player),
                                           ball: plane.coordinate(shot.ball),
                                           landing: plane.coordinate(shot.landing)))
            }
        }

        return SimulatedRound(fixes: measure(path, start: start),
                              truePath: path.map { plane.coordinate($0) },
                              shots: shots)
    }

    private mutating func makeLayout(_ hole: Hole) -> HoleLayout {
        let teeFeature = hole.tees[teeName].flatMap { course.findFeature(id: $0) }
        let centerline = hole.centerline.map(plane.point)
        let tee = teeFeature.map { plane.point(PolygonGeometry.centroid(of: $0.polygon)) } ?? centerline[0]

        // The pin is somewhere on the green, not always in the middle
        var pin = centerline[centerline.count - 1]
        if let green = hole.green(from: course.features) {
            let center = plane.point(PolygonGeometry.centroid(of: green.polygon))
            pin = center
            for _ in 0..<20 {
                let candidate = center + Vec(x: random.gaussian(deviation: 3), y: random.gaussian(deviation: 3))
                if hole.onGreen(plane.coordinate(candidate), from: course.features) {
                    pin = candidate
                    break
                }
            }
        }
        return HoleLayout(hole: hole, tee: tee, centerline: centerline, pin: pin)
    }

    /// Beside the tee markers, where players stand while others tee off.
    private func waitingSpot(_ layout: HoleLayout) -> Vec {
        let direction = (point(at: progress(of: layout.tee, on: layout.centerline) + 50, on: layout.centerline) - layout.tee).unit
        return layout.tee + direction.left * 4 - direction * 2
    }

    private mutating func planHole(_ layout: HoleLayout, from start: Vec, nextTee: Vec?, steps: inout [Step]) -> [PlannedShot] {
        var shots: [PlannedShot] = []
        var player = start
        var ball = layout.tee
        let teeSide = waitingSpot(layout)

        // The group ahead clears, or partners hit first
        wait(near: player, seconds: random.uniform(20...80), player: &player, steps: &steps)

        var stroke = 0
        while true {
            stroke += 1
            let onGreen = isOnGreen(ball, layout)
            let plan = planShot(stroke: stroke, from: ball, onGreen: onGreen, layout: layout)
            let direction = (plan.aim - ball).unit
            let behind = ball - direction * (onGreen ? 2 : 3)
            let address = ball + direction.left * (onGreen ? 0.5 : 0.9)

            walk(to: behind, player: &player, steps: &steps)
            if onGreen, ball.distance(to: layout.pin) > 4, !shots.contains(where: { isOnGreen($0.ball, layout) }) {
                // Read the first putt from the far side of the hole, then come back
                walk(to: layout.pin + direction * 1.5 + direction.left * 1.0, speed: 0.9, player: &player, steps: &steps)
                steps.append(.stand(at: player, seconds: 6, flexible: false))
                walk(to: behind, speed: 0.9, player: &player, steps: &steps)
                // Partners putt in turn
                wait(near: player, seconds: random.uniform(15...50), player: &player, steps: &steps)
                walk(to: behind, speed: 0.9, player: &player, steps: &steps)
            }

            // Line up from behind the ball, step in, then the routine ends with the swing
            steps.append(.stand(at: behind, seconds: 6, flexible: false))
            steps.append(.walk(path: [behind, address], speed: 0.8))
            player = address
            let routine: Double = stroke == 1 ? 30 : onGreen ? 12 : ball.distance(to: layout.pin) <= 45 ? 18 : 25
            steps.append(.stand(at: address, seconds: routine, flexible: false))
            shots.append(PlannedShot(stroke: stroke, swingAfterStep: steps.count - 1,
                                     player: address, ball: ball, landing: plan.landing))
            // Watch the ball
            steps.append(.stand(at: address, seconds: random.uniform(3...6), flexible: false))

            if plan.landing == layout.pin {
                break
            }

            if stroke == 1 {
                // Step aside while partners tee off
                walk(to: teeSide, speed: 1.0, player: &player, steps: &steps)
                wait(near: player, seconds: random.uniform(40...110), player: &player, steps: &steps)
            }

            let distance = player.distance(to: plan.landing)
            if distance > 120, random.chance(0.6) {
                // A partner's ball is on the way: stop beside it while they hit
                let line = (plan.landing - player).unit
                let side: Double = random.chance(0.5) ? 1 : -1
                let partner = player + line * (distance * random.uniform(0.45...0.8)) + line.left * (side * random.uniform(12...30))
                if !isInWater(partner) {
                    walk(to: partner, player: &player, steps: &steps)
                    wait(near: player, seconds: random.uniform(25...45), player: &player, steps: &steps)
                }
            } else if isOnGreen(plan.landing, layout), !onGreen, distance > 20 {
                // Wait short of the green while partners hit up
                let short = plan.landing + (player - plan.landing).unit * 12
                if !isInWater(short) {
                    walk(to: short, player: &player, steps: &steps)
                    wait(near: player, seconds: random.uniform(20...60), player: &player, steps: &steps)
                }
            }
            ball = plan.landing
        }

        // Take the ball out of the hole, then wait beside the green while partners putt out
        walk(to: layout.pin + Vec(x: 0.4, y: 0.3), speed: 0.9, player: &player, steps: &steps)
        steps.append(.stand(at: player, seconds: 4, flexible: false))
        let exitDirection = ((nextTee ?? layout.tee) - layout.pin).unit
        walk(to: layout.pin + exitDirection * 14, speed: 1.0, player: &player, steps: &steps)
        wait(near: player, seconds: random.uniform(40...100), player: &player, steps: &steps)

        if let nextTee {
            walk(to: nextTee, player: &player, steps: &steps)
        }
        return shots
    }

    // MARK: - Shots

    private mutating func planShot(stroke: Int, from ball: Vec, onGreen: Bool, layout: HoleLayout) -> (aim: Vec, landing: Vec) {
        let pin = layout.pin
        let remaining = ball.distance(to: pin)

        // Nobody putts forever
        if stroke >= 10 {
            return (pin, pin)
        }

        if onGreen {
            // Tap-in
            if remaining <= 0.6 {
                return (pin, pin)
            }
            // Putts are hit to finish a little past the hole. One drops only if it is on line
            // and not going too fast: about 1 in 2 from 1.5 m, 1 in 5 from 4 m, 1 in 20 from 10 m.
            let direction = (pin - ball).unit
            let long = random.gaussian(mean: 0.3, deviation: 0.10 * remaining + 0.15)
            let wide = random.gaussian(deviation: 0.04 * remaining + 0.02)
            if abs(wide) < 0.06, (-0.05...1.2).contains(long) {
                return (pin, pin)
            }
            return (pin, pin + direction * long + direction.left * wide)
        }

        for _ in 0..<10 {
            let aim: Vec
            let long: Double
            let wide: Double
            if remaining <= 45 {
                // Chip or pitch
                aim = pin
                long = 0.12 * remaining + 1
                wide = 0.08 * remaining + 0.5
            } else if remaining <= 190 {
                // Approach
                aim = pin
                long = 0.08 * remaining
                wide = 0.08 * remaining
            } else {
                // Full shot down the centerline
                let carry = random.gaussian(mean: stroke == 1 ? 205 : 180, deviation: 12)
                aim = point(at: progress(of: ball, on: layout.centerline) + carry, on: layout.centerline)
                long = 0.05 * carry
                wide = 0.08 * carry
            }
            let direction = (aim - ball).unit
            var landing = aim + direction * random.gaussian(deviation: long) + direction.left * random.gaussian(deviation: wide)
            if remaining > 45, random.chance(0.12) {
                // A mishit: well short and further off line
                let reach = ball.distance(to: aim) * random.uniform(0.4...0.75)
                landing = ball + direction * reach + direction.left * random.gaussian(deviation: 2 * wide * reach / ball.distance(to: aim))
            }
            // A ball at the water's edge is as good as wet: there is nowhere to stand
            if !isNearWater(landing) {
                return (aim, landing)
            }
        }
        let aim = remaining <= 190 ? pin : point(at: progress(of: ball, on: layout.centerline) + 180, on: layout.centerline)
        return (aim, aim)
    }

    // MARK: - Moving

    /// Walks to `destination` on a curved, wandering path that stays out of the water.
    private mutating func walk(to destination: Vec, speed: Double? = nil, player: inout Vec, steps: inout [Step]) {
        let distance = player.distance(to: destination)
        guard distance > 0.3 else {
            player = destination
            return
        }
        let pace = speed ?? random.uniform(1.2...1.5)
        steps.append(.walk(path: path(from: player, to: destination), speed: pace))
        player = destination
    }

    private mutating func path(from a: Vec, to b: Vec) -> [Vec] {
        let waypoints = route(from: a, to: b)
        var points: [Vec] = [a]
        for (start, end) in zip(waypoints, waypoints.dropFirst()) {
            points += curve(from: start, to: end, gentle: waypoints.count > 2).dropFirst()
        }
        return points
    }

    /// A bent, weaving line from `a` to `b`. Falls back to a straight one beside water.
    private mutating func curve(from a: Vec, to b: Vec, gentle: Bool) -> [Vec] {
        let distance = a.distance(to: b)
        let side = (b - a).unit.left
        let count = max(2, Int(distance / 2))

        for _ in 0..<6 {
            let bend = random.gaussian(deviation: gentle ? 0.02 : 0.07) * distance
            let control = a + (b - a) * 0.5 + side * max(-0.2 * distance, min(0.2 * distance, bend))

            // Two slow weaves, faded out at both ends and on short walks
            let scale = min(1, distance / 60) * (gentle ? 0.4 : 1)
            let bigSize = random.uniform(1...3) * scale, bigLength = random.uniform(60...120), bigPhase = random.uniform(0...(2 * .pi))
            let smallSize = random.uniform(0.4...1.2) * scale, smallLength = random.uniform(15...35), smallPhase = random.uniform(0...(2 * .pi))

            var points: [Vec] = []
            for i in 0...count {
                let t = Double(i) / Double(count)
                let bezier = a * ((1 - t) * (1 - t)) + control * (2 * t * (1 - t)) + b * (t * t)
                let along = t * distance
                let weave = bigSize * sin(2 * .pi * along / bigLength + bigPhase) + smallSize * sin(2 * .pi * along / smallLength + smallPhase)
                points.append(bezier + side * (weave * sin(.pi * t)))
            }
            if !points.contains(where: { isInWater($0) }) {
                return points
            }
        }
        return (0...count).map { a + (b - a) * (Double($0) / Double(count)) }
    }

    /// Waypoints from `a` to `b` around any ponds in the way: the shortest dry route through
    /// points set just off the ponds' banks.
    private func route(from a: Vec, to b: Vec) -> [Vec] {
        guard crossesWater(a, b) else { return [a, b] }

        let reach = 80.0
        let nearby = ponds.flatMap(\.bankPoints).filter {
            $0.x >= min(a.x, b.x) - reach && $0.x <= max(a.x, b.x) + reach &&
            $0.y >= min(a.y, b.y) - reach && $0.y <= max(a.y, b.y) + reach && !isInWater($0)
        }
        let nodes = [a, b] + nearby

        // Dijkstra. Two points connect when the straight line between them stays dry.
        var distance = [Double](repeating: .infinity, count: nodes.count)
        var previous = [Int?](repeating: nil, count: nodes.count)
        var open = Set(nodes.indices)
        distance[0] = 0
        while let current = open.min(by: { distance[$0] < distance[$1] }), distance[current] < .infinity {
            open.remove(current)
            if current == 1 { break }
            for next in open {
                let length = distance[current] + nodes[current].distance(to: nodes[next])
                if length < distance[next], !crossesWater(nodes[current], nodes[next]) {
                    distance[next] = length
                    previous[next] = current
                }
            }
        }

        guard previous[1] != nil else { return [a, b] }
        var way = [b]
        var index = 1
        while let before = previous[index] {
            way.append(nodes[before])
            index = before
        }
        return way.reversed()
    }

    /// Waits around one spot. A person does not stand still for minutes, so long waits
    /// include short strolls.
    private mutating func wait(near spot: Vec, seconds: Double, player: inout Vec, steps: inout [Step]) {
        var remaining = seconds
        while remaining > 0 {
            let still = min(remaining, random.uniform(20...45))
            steps.append(.stand(at: player, seconds: still, flexible: true))
            remaining -= still
            if remaining > 10 {
                let angle = random.uniform(0...(2 * .pi))
                let stroll = spot + Vec(x: cos(angle), y: sin(angle)) * random.uniform(1.5...5)
                if !isInWater(stroll) {
                    steps.append(.walk(path: [player, stroll], speed: 0.8))
                    player = stroll
                }
            }
        }
    }

    // MARK: - Time

    /// Seconds for each step, with waits stretched or squeezed so the steps take exactly `total`.
    private func fit(_ steps: [Step], into total: Double) -> [Double] {
        var walking = 0.0, fixed = 0.0, flexible = 0.0
        for step in steps {
            switch step {
            case .walk(let path, let speed): walking += length(of: path) / speed
            case .stand(_, let seconds, let isFlexible): if isFlexible { flexible += seconds } else { fixed += seconds }
            }
        }

        var waitScale = (total - walking - fixed) / flexible
        var walkScale = 1.0
        if waitScale < 0.2 {
            // Too little time left for waiting: the group walks faster
            waitScale = 0.2
            walkScale = (total - fixed - waitScale * flexible) / walking
        }

        return steps.map { step in
            switch step {
            case .walk(let path, let speed): return length(of: path) / speed * walkScale
            case .stand(_, let seconds, let isFlexible): return isFlexible ? seconds * waitScale : seconds
            }
        }
    }

    /// The player's true position at each whole second.
    private mutating func sample(_ steps: [Step], durations: [Double], seconds: Int) -> [Vec] {
        var result: [Vec] = []
        var index = 0
        var stepStart = 0.0
        var sway = Vec(x: 0, y: 0)

        for second in 0..<seconds {
            let time = Double(second)
            while index < steps.count - 1, time >= stepStart + durations[index] {
                stepStart += durations[index]
                index += 1
            }
            switch steps[index] {
            case .stand(let spot, _, _):
                // Shifting weight, practice swings
                sway = sway * 0.8 + Vec(x: random.gaussian(deviation: 0.12), y: random.gaussian(deviation: 0.12))
                result.append(spot + sway)
            case .walk(let path, _):
                sway = sway * 0.5
                let fraction = durations[index] > 0 ? min(1, (time - stepStart) / durations[index]) : 1
                result.append(point(at: fraction * length(of: path), on: path) + sway)
            }
        }
        return result
    }

    private func endPoint(of steps: [Step]) -> Vec? {
        switch steps.last {
        case .stand(let spot, _, _): return spot
        case .walk(let path, _): return path.last
        case nil: return nil
        }
    }

    // MARK: - GPS

    /// Turns true positions into GPS fixes. The error drifts slowly by a couple of meters, as
    /// real GPS error does, with a little jitter on top. Course files have no elevation, so
    /// the ground is a gentle made-up surface.
    private mutating func measure(_ path: [Vec], start: Date) -> [CLLocation] {
        let drift = exp(-1.0 / 40), driftKick = (1 - drift * drift).squareRoot() * 2.0
        let climb = exp(-1.0 / 60), climbKick = (1 - climb * climb).squareRoot() * 3.0
        var error = Vec(x: random.gaussian(deviation: 2), y: random.gaussian(deviation: 2))
        var heightError = random.gaussian(deviation: 3)

        var fixes: [CLLocation] = []
        for (index, point) in path.enumerated() {
            error = error * drift + Vec(x: random.gaussian(deviation: driftKick), y: random.gaussian(deviation: driftKick))
            heightError = heightError * climb + random.gaussian(deviation: climbKick)
            let jitter = Vec(x: random.gaussian(deviation: 0.3), y: random.gaussian(deviation: 0.3))

            let ground = 1625 + 0.004 * point.x - 0.006 * point.y + 1.5 * sin(point.x / 90) * cos(point.y / 70)
            let step = index > 0 ? point - path[index - 1] : Vec(x: 0, y: 0)
            let heading = atan2(step.x, step.y) * 180 / .pi

            fixes.append(CLLocation(coordinate: plane.coordinate(point + error + jitter).clCoordinate,
                                    altitude: ground + heightError + random.gaussian(deviation: 0.3),
                                    horizontalAccuracy: min(15, max(3, 4 + error.length * 0.6 + random.uniform(0...1))),
                                    verticalAccuracy: min(20, max(4, 5 + abs(heightError) * 0.6)),
                                    course: step.length < 0.2 ? -1 : (heading < 0 ? heading + 360 : heading),
                                    speed: step.length,
                                    timestamp: start.addingTimeInterval(Double(index))))
        }
        return fixes
    }

    // MARK: - Geometry

    private func isOnGreen(_ point: Vec, _ layout: HoleLayout) -> Bool {
        layout.hole.onGreen(plane.coordinate(point), from: course.features)
    }

    private func isInWater(_ point: Vec) -> Bool {
        ponds.contains { $0.contains(point) }
    }

    /// True within 4 meters of water.
    private func isNearWater(_ point: Vec) -> Bool {
        isInWater(point) || (0..<8).contains { step in
            let angle = Double(step) * .pi / 4
            return isInWater(point + Vec(x: cos(angle), y: sin(angle)) * 4)
        }
    }

    /// True when the straight line from `a` to `b` passes over water.
    private func crossesWater(_ a: Vec, _ b: Vec) -> Bool {
        let near = ponds.filter { $0.mayTouch(a, b) }
        guard !near.isEmpty else { return false }
        let count = max(1, Int(a.distance(to: b) / 1.5))
        return (0...count).contains { step in
            let point = a + (b - a) * (Double(step) / Double(count))
            return near.contains { $0.contains(point) }
        }
    }

    private func length(of line: [Vec]) -> Double {
        zip(line, line.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// The point `distance` meters along `line`, clamped to its ends.
    private func point(at distance: Double, on line: [Vec]) -> Vec {
        var remaining = max(0, distance)
        for (a, b) in zip(line, line.dropFirst()) {
            let segment = a.distance(to: b)
            if remaining <= segment, segment > 0 {
                return a + (b - a) * (remaining / segment)
            }
            remaining -= segment
        }
        return line[line.count - 1]
    }

    /// How far along `line` the point closest to `point` is.
    private func progress(of point: Vec, on line: [Vec]) -> Double {
        var best = 0.0, bestDistance = Double.infinity, walked = 0.0
        for (a, b) in zip(line, line.dropFirst()) {
            let segment = b - a
            let lengthSquared = segment.x * segment.x + segment.y * segment.y
            let t = lengthSquared > 0 ? max(0, min(1, ((point.x - a.x) * segment.x + (point.y - a.y) * segment.y) / lengthSquared)) : 0
            let distance = point.distance(to: a + segment * t)
            if distance < bestDistance {
                bestDistance = distance
                best = walked + segment.length * t
            }
            walked += segment.length
        }
        return best
    }
}
