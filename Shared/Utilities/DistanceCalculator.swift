import CoreLocation
import CourseData

struct GreenDistances {
    let front: Int
    let middle: Int
    let back: Int
}

struct FeatureDistance: Identifiable {
    let feature: Feature
    let distanceYards: Int
    /// The point of the feature closest to the player: where the hazard starts.
    let nearestPoint: Coordinate

    var id: Int { feature.id }
}

enum DistanceCalculator {
    private static let metersToYards = 1.09361

    static func yards(from a: CLLocation, to b: CLLocation) -> Double {
        a.distance(from: b) * metersToYards
    }

    static func yards(from a: BallMark, to b: BallMark) -> Double {
        yards(from: a.location, to: b.location)
    }

    static func formattedYards(from a: CLLocation, to b: CLLocation) -> String {
        "\(Int(yards(from: a, to: b))) yds"
    }

    static func formattedYards(from a: BallMark, to b: BallMark) -> String {
        formattedYards(from: a.location, to: b.location)
    }

    static func greenDistances(from location: CLLocation, green: Feature, direction: Vector2D) -> GreenDistances {
        let playerCoord = Coordinate(location.coordinate)
        let playerProj = playerCoord.latitude * direction.dx + playerCoord.longitude * direction.dy

        func signedYards(to point: Coordinate) -> Int {
            let dist = Int(yards(from: location, to: point.clLocation))
            let pointProj = point.latitude * direction.dx + point.longitude * direction.dy
            return playerProj > pointProj ? -dist : dist
        }

        return GreenDistances(
            front: signedYards(to: green.front(vector: direction)),
            middle: signedYards(to: green.middle()),
            back: signedYards(to: green.back(vector: direction))
        )
    }

    private static let maxAngle = 45.0 * .pi / 180 // features beyond 45° off line of play are excluded

    static func featuresAhead(from location: CLLocation, features: [Feature], green: Feature, limit: Int = 3) -> [FeatureDistance] {
        let coord = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        if PolygonGeometry.contains(coord, in: green.polygon) { return [] }

        let greenCenter = green.center
        let greenLoc = greenCenter.clLocation
        let distToGreen = location.distance(from: greenLoc)

        // Player → green vector for angle check
        let toGreenLat = greenCenter.latitude - coord.latitude
        let toGreenLon = greenCenter.longitude - coord.longitude
        let toGreenMag = sqrt(toGreenLat * toGreenLat + toGreenLon * toGreenLon)

        guard toGreenMag > 0 else { return [] }

        return features.compactMap { feature in
            guard feature.type == .bunker || feature.type == .water else { return nil }

            let nearest = PolygonGeometry.nearestPoint(on: feature.polygon, to: coord)
            let nearestLoc = nearest.clLocation
            let distToFeature = location.distance(from: nearestLoc)
            let featureToGreen = nearestLoc.distance(from: greenLoc)

            guard featureToGreen < distToGreen else { return nil }

            // Angle between player→nearest point and player→green
            let toFeatLat = nearest.latitude - coord.latitude
            let toFeatLon = nearest.longitude - coord.longitude
            let toFeatMag = sqrt(toFeatLat * toFeatLat + toFeatLon * toFeatLon)
            guard toFeatMag > 0 else { return nil }

            let dot = toFeatLat * toGreenLat + toFeatLon * toGreenLon
            let cosAngle = min(max(dot / (toFeatMag * toGreenMag), -1), 1)
            guard acos(cosAngle) <= maxAngle else { return nil }

            return FeatureDistance(
                feature: feature,
                distanceYards: Int(distToFeature * metersToYards),
                nearestPoint: nearest
            )
        }
        .sorted { $0.distanceYards < $1.distanceYards }
        .prefix(limit)
        .map { $0 }
    }
}
