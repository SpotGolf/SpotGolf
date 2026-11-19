import Foundation

/// Distances over a golf hole on a flat map (equirectangular). Plenty accurate at that
/// scale and far cheaper than `CLLocation.distance` for every point-to-point pair.
enum LocalDistance {
    static let metersPerDegree = 111_320.0

    static func meters(fromLat latA: Double, lon lonA: Double, toLat latB: Double, lon lonB: Double) -> Double {
        let dLat = (latB - latA) * metersPerDegree
        let dLon = (lonB - lonA) * metersPerDegree * cos(latA * .pi / 180)
        return (dLat * dLat + dLon * dLon).squareRoot()
    }

    /// Meters from a point to the nearest point on a polyline, or nil when it has fewer than 2 points.
    static func meters(fromLat lat: Double, lon: Double, toPolyline line: [(latitude: Double, longitude: Double)]) -> Double? {
        nearest(fromLat: lat, lon: lon, onPolyline: line)?.meters
    }

    /// Meters from a point to the nearest point on a polyline, and whether that point is the
    /// polyline's last point: the point lies beyond the line's end. Nil when the polyline has
    /// fewer than 2 points.
    static func nearest(fromLat lat: Double, lon: Double,
                        onPolyline line: [(latitude: Double, longitude: Double)]) -> (meters: Double, isLineEnd: Bool)? {
        guard line.count >= 2 else { return nil }
        let cosLat = cos(lat * .pi / 180)
        // Meters east and north of the point
        func local(_ p: (latitude: Double, longitude: Double)) -> (x: Double, y: Double) {
            ((p.longitude - lon) * metersPerDegree * cosLat, (p.latitude - lat) * metersPerDegree)
        }
        var best = Double.infinity
        var isLineEnd = false
        for i in 0..<(line.count - 1) {
            let a = local(line[i]), b = local(line[i + 1])
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared > 0 ? max(0, min(1, -(a.x * dx + a.y * dy) / lengthSquared)) : 0
            let meters = ((a.x + t * dx) * (a.x + t * dx) + (a.y + t * dy) * (a.y + t * dy)).squareRoot()
            if meters < best {
                best = meters
                isLineEnd = i == line.count - 2 && t >= 1
            }
        }
        return (best, isLineEnd)
    }
}
