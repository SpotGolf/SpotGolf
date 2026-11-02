import CoreLocation
import CourseDataSwift

/// Says when the player has left one hole's green, from GPS fixes: enough fixes on it, then a
/// fix far enough from its edge. Hole advance and the end round prompt both use it.
/// See plans/2026-10-01-hole-advance-on-green-exit.md for how the numbers were chosen.
struct GreenExit {
    /// The player must be this far from the green's edge, past where a bag is usually left.
    static let exitDistance: CLLocationDistance = 20
    /// Fixes inside the green, in total, before leaving it counts. About 20 s; GPS drift and
    /// walking across a corner give fewer.
    static let minGreenFixes = 20

    let shape: HoleShape
    private var greenFixes = 0
    /// The latest fix's meters from the green's edge, or nil without a green or a fix.
    private var toGreen: CLLocationDistance?
    /// When the latest fix inside the green was taken, or nil before one.
    private(set) var lastOnGreenAt: Date?

    init(shape: HoleShape = HoleShape()) {
        self.shape = shape
    }

    /// Takes a fix. Returns its meters from the green's edge, zero on the green, or nil when the
    /// hole has no green.
    @discardableResult
    mutating func update(_ point: Coordinate, at timestamp: Date) -> CLLocationDistance? {
        toGreen = shape.metersToGreen(point)
        if toGreen == 0 {
            greenFixes += 1
            lastOnGreenAt = timestamp
        }
        return toGreen
    }

    /// Enough fixes on the green, and the latest one far enough from it.
    var hasLeft: Bool {
        guard greenFixes >= Self.minGreenFixes, let toGreen else { return false }
        return toGreen >= Self.exitDistance
    }
}
