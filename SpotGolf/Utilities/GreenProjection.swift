import CoreGraphics
import CoreLocation
import CourseDataSwift

/// Where Green View draws the ground: a flat projection around the green's center, turned so
/// the hole's direction of play points up, zoomed and panned by the player. It plays the part
/// `MapProxy` plays on the map. At the size of a green, flat ground is off by well under a
/// centimeter.
///
/// Ground points are taken in meters to the right and up from the green's center, as the screen
/// shows them, so fitting and the pan limits are plain boxes.
struct GreenProjection: Equatable {
    /// Green View opens on the green with this much ground around it, in meters (5 yd).
    static let openMargin = 4.572
    /// Zooming out stops at the green with this much ground around it, in meters (15 yd).
    static let zoomOutMargin = 13.716
    /// Zooming in stops here: 4 points per inch, so a 1 ft gap is 48 points.
    static let maxPointsPerMeter = 4 / 0.0254

    /// The green's center, where ground points are measured from.
    let origin: CLLocationCoordinate2D
    /// Degrees clockwise from north that point up on the screen.
    let heading: Double
    /// The green's outline as ground points.
    let green: [CGPoint]
    var size: CGSize
    var pointsPerMeter: Double
    /// The ground point at the middle of the screen.
    var focus: CGPoint

    /// Fitted to `green` with `openMargin` around it. Nil for an outline without points, or
    /// before the view has a size.
    init?(green polygon: [Coordinate], heading: Double, size: CGSize) {
        guard !polygon.isEmpty, size.width > 0, size.height > 0 else { return nil }
        let origin = PolygonGeometry.centroid(of: polygon).clCoordinate
        self.init(origin: origin, heading: heading,
                  green: polygon.map { Self.ground($0.clCoordinate, origin: origin, heading: heading) }, size: size)
    }

    private init(origin: CLLocationCoordinate2D, heading: Double, green: [CGPoint], size: CGSize) {
        self.origin = origin
        self.heading = heading
        self.green = green
        self.size = size
        let bounds = Self.bounds(of: green)
        pointsPerMeter = Self.fittingScale(bounds, margin: Self.openMargin, in: size)
        focus = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    // MARK: - Ground and screen

    /// `coordinate` as meters right and up from the green's center.
    func ground(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
        Self.ground(coordinate, origin: origin, heading: heading)
    }

    private static func ground(_ coordinate: CLLocationCoordinate2D, origin: CLLocationCoordinate2D,
                               heading: Double) -> CGPoint {
        let north = (coordinate.latitude - origin.latitude) * LocalDistance.metersPerDegree
        let east = (coordinate.longitude - origin.longitude) * LocalDistance.metersPerDegree * cos(origin.latitude * .pi / 180)
        let radians = heading * .pi / 180
        return CGPoint(x: east * cos(radians) - north * sin(radians),
                       y: east * sin(radians) + north * cos(radians))
    }

    /// The coordinate of a ground point.
    func coordinate(ofGround point: CGPoint) -> CLLocationCoordinate2D {
        let radians = heading * .pi / 180
        let east = point.x * cos(radians) + point.y * sin(radians)
        let north = -point.x * sin(radians) + point.y * cos(radians)
        return CLLocationCoordinate2D(
            latitude: origin.latitude + north / LocalDistance.metersPerDegree,
            longitude: origin.longitude + east / (LocalDistance.metersPerDegree * cos(origin.latitude * .pi / 180)))
    }

    /// Where `coordinate` is on the screen.
    func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
        screen(ofGround: ground(coordinate))
    }

    /// The coordinate under a point on the screen.
    func coordinate(at point: CGPoint) -> CLLocationCoordinate2D {
        coordinate(ofGround: ground(atScreen: point))
    }

    func screen(ofGround point: CGPoint) -> CGPoint {
        CGPoint(x: size.width / 2 + (point.x - focus.x) * pointsPerMeter,
                y: size.height / 2 - (point.y - focus.y) * pointsPerMeter)
    }

    private func ground(atScreen point: CGPoint) -> CGPoint {
        CGPoint(x: focus.x + (point.x - size.width / 2) / pointsPerMeter,
                y: focus.y - (point.y - size.height / 2) / pointsPerMeter)
    }

    // MARK: - Zoom and pan

    /// The least zoomed in: the green with `zoomOutMargin` around it.
    var minPointsPerMeter: Double {
        min(Self.fittingScale(Self.bounds(of: green), margin: Self.zoomOutMargin, in: size), Self.maxPointsPerMeter)
    }

    /// Zooms by `factor` (above 1 zooms in), keeping the ground under `anchor` where it is.
    mutating func zoom(by factor: Double, at anchor: CGPoint) {
        let held = ground(atScreen: anchor)
        pointsPerMeter = min(max(pointsPerMeter * factor, minPointsPerMeter), Self.maxPointsPerMeter)
        focus = CGPoint(x: held.x - (anchor.x - size.width / 2) / pointsPerMeter,
                        y: held.y + (anchor.y - size.height / 2) / pointsPerMeter)
        clampFocus()
    }

    /// Moves the ground with a finger that moved by `translation` points.
    mutating func pan(by translation: CGSize) {
        focus = CGPoint(x: focus.x - translation.width / pointsPerMeter,
                        y: focus.y + translation.height / pointsPerMeter)
        clampFocus()
    }

    /// Takes a new view size, keeping the zoom within its limits.
    mutating func resize(to newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        pointsPerMeter = min(max(pointsPerMeter, minPointsPerMeter), Self.maxPointsPerMeter)
        clampFocus()
    }

    /// Keeps the middle of the screen over the green and `zoomOutMargin` around it.
    private mutating func clampFocus() {
        let limit = Self.bounds(of: green).insetBy(dx: -Self.zoomOutMargin, dy: -Self.zoomOutMargin)
        focus = CGPoint(x: min(max(focus.x, limit.minX), limit.maxX), y: min(max(focus.y, limit.minY), limit.maxY))
    }

    // MARK: - Fitting

    static func bounds(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    /// Points per meter that fit `bounds` with `margin` meters around it into `size`.
    static func fittingScale(_ bounds: CGRect, margin: Double, in size: CGSize) -> Double {
        let width = bounds.width + 2 * margin, height = bounds.height + 2 * margin
        return min(size.width / width, size.height / height)
    }

    static func == (lhs: GreenProjection, rhs: GreenProjection) -> Bool {
        lhs.origin.latitude == rhs.origin.latitude && lhs.origin.longitude == rhs.origin.longitude
            && lhs.heading == rhs.heading && lhs.green == rhs.green && lhs.size == rhs.size
            && lhs.pointsPerMeter == rhs.pointsPerMeter && lhs.focus == rhs.focus
    }
}
