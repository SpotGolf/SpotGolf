import CourseDataSwift
import Foundation

/// Where a ball lies, for the strokes it takes to hole out from there.
enum Lie: Equatable, Sendable {
    case fairway, rough, sand, green, water
}

/// The lie anywhere near one hole, looked up on a 2-yard grid. Each square's lie is worked out
/// at its center the first time it is asked for, and kept. Water and bunkers come from the whole
/// course, since a ball can reach another hole's; the green and fairways are the hole's own, so
/// another hole's are rough. See plans/2026-11-02-caddie-club-and-aim.md, section 3.
final class LieGrid {
    /// A square's side: 2 yards, in meters.
    static let cellSize = 2 * 0.9144

    let plane: GroundPlane
    private let water: [GroundPolygon]
    private let sand: [GroundPolygon]
    private let green: [GroundPolygon]
    private let fairway: [GroundPolygon]
    /// The hole's own fairways and green, where the Caddie's aim point must be.
    private let landing: [GroundPolygon]
    /// The hole's centerline, from the tee to the green. Empty when the hole has none.
    private let centerline: [GroundPoint]
    private var cells: [Int: Lie] = [:]

    /// The squares worked out so far.
    var cellCount: Int { cells.count }

    init(course: Course, hole: Hole, plane: GroundPlane) {
        self.plane = plane
        func polygons(_ features: [Feature]) -> [GroundPolygon] {
            features.compactMap { GroundPolygon($0.polygon.map(plane.point)) }
        }
        let own = course.features(for: hole)
        water = polygons(course.features.filter { $0.type == .water })
        sand = polygons(course.features.filter { $0.type == .bunker })
        green = polygons(own.filter { $0.type == .green })
        fairway = polygons(own.filter { $0.type == .fairway || $0.type == .tee })
        landing = polygons(own.filter { $0.type == .fairway || $0.type == .green })
        centerline = hole.centerline(from: course.features)?.polygon.map(plane.point) ?? []
    }

    /// True when the hole has a centerline.
    var hasCenterline: Bool { centerline.count >= 2 }

    /// True when `point` is on the hole's own fairway or green, and not in water or sand there.
    func isLanding(_ point: GroundPoint) -> Bool {
        guard landing.contains(where: { $0.contains(point) }) else { return false }
        let lie = lie(at: point)
        return lie == .fairway || lie == .green
    }

    /// True when `point` is within `meters` of the hole's centerline. False without one.
    func isNearCenterline(_ point: GroundPoint, within meters: Double) -> Bool {
        guard hasCenterline else { return false }
        return zip(centerline, centerline.dropFirst()).contains { a, b in
            let segment = b - a
            let lengthSquared = segment.x * segment.x + segment.y * segment.y
            let t = lengthSquared > 0
                ? max(0, min(1, ((point.x - a.x) * segment.x + (point.y - a.y) * segment.y) / lengthSquared)) : 0
            return point.distance(to: a + segment * t) <= meters
        }
    }

    /// Hole `index` of the round, flattened around its green's center. Nil without a green.
    convenience init?(round: Round, holeIndex index: Int) {
        guard let hole = round.courseHole(at: index), let green = round.green(holeIndex: index) else { return nil }
        self.init(course: round.course, hole: hole, plane: GroundPlane(origin: green.center))
    }

    /// The water and sand shapes within `reach` meters of `point`, for the map to mark.
    func hazards(near point: GroundPoint, reach: Double) -> [[GroundPoint]] {
        (water + sand).filter { $0.isNear(point, reach: reach) }.map(\.points)
    }

    func lie(at point: GroundPoint) -> Lie {
        let column = Int((point.x / Self.cellSize).rounded(.down))
        let row = Int((point.y / Self.cellSize).rounded(.down))
        // Two 32-bit halves of one key
        let key = column << 32 | (row & 0xFFFF_FFFF)
        if let lie = cells[key] { return lie }
        let center = GroundPoint(x: (Double(column) + 0.5) * Self.cellSize, y: (Double(row) + 0.5) * Self.cellSize)
        let lie = workOutLie(at: center)
        cells[key] = lie
        return lie
    }

    /// Where a ball that stopped in water at `end`, hit from `start`, last went into the water:
    /// found by stepping back from `end` toward `start` until it leaves the water. `start` when
    /// the whole line is water.
    func waterEntry(from start: GroundPoint, to end: GroundPoint) -> GroundPoint {
        let length = start.distance(to: end)
        let step = Self.cellSize / 2
        guard length > step else { return start }
        let back = (start - end) * (step / length)
        var point = end
        var walked = 0.0
        while walked + step < length {
            let next = point + back
            if lie(at: next) != .water { return point }
            point = next
            walked += step
        }
        return start
    }

    private func workOutLie(at point: GroundPoint) -> Lie {
        if water.contains(where: { $0.contains(point) }) { return .water }
        if sand.contains(where: { $0.contains(point) }) { return .sand }
        if green.contains(where: { $0.contains(point) }) { return .green }
        if fairway.contains(where: { $0.contains(point) }) { return .fairway }
        return .rough
    }
}

/// A closed shape on the ground, with its bounding box to skip it fast.
struct GroundPolygon {
    let points: [GroundPoint]
    private let minX: Double
    private let maxX: Double
    private let minY: Double
    private let maxY: Double

    /// Nil with fewer than 3 points.
    init?(_ points: [GroundPoint]) {
        guard points.count >= 3 else { return nil }
        self.points = points
        minX = points.map(\.x).min()!
        maxX = points.map(\.x).max()!
        minY = points.map(\.y).min()!
        maxY = points.map(\.y).max()!
    }

    /// True when the shape's bounding box comes within `reach` of `point`.
    func isNear(_ point: GroundPoint, reach: Double) -> Bool {
        point.x >= minX - reach && point.x <= maxX + reach && point.y >= minY - reach && point.y <= maxY + reach
    }

    /// By the even-odd rule, as `PolygonGeometry.contains` does.
    func contains(_ point: GroundPoint) -> Bool {
        guard point.x >= minX, point.x <= maxX, point.y >= minY, point.y <= maxY else { return false }
        var inside = false
        var previous = points[points.count - 1]
        for current in points {
            if (current.y > point.y) != (previous.y > point.y),
               point.x < (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x {
                inside.toggle()
            }
            previous = current
        }
        return inside
    }
}
