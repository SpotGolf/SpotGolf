import CoreLocation

/// The GPS track as the map draws it.
enum TrackLine {
    /// Fixes closer than this to the last one kept are left out. GPS drift while the player stands
    /// still is about this much, and drawn it would crumple the line into a blot.
    static let minimumSpacing: CLLocationDistance = 3

    /// The track's coordinates at least `minimumSpacing` apart, in order: the first fix, then each
    /// fix that far from the last one kept.
    static func coordinates(of track: [TrackPoint],
                            minimumSpacing: CLLocationDistance = minimumSpacing) -> [CLLocationCoordinate2D] {
        var kept: [CLLocation] = []
        for point in track {
            let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
            if let last = kept.last, location.distance(from: last) < minimumSpacing { continue }
            kept.append(location)
        }
        return kept.map(\.coordinate)
    }
}
