import CoreLocation
import CourseData

struct GreenDistances {
    let front: Int
    let middle: Int
    let back: Int
}

struct FeatureDistance {
    let feature: Feature
    let distanceYards: Int
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

    static func featuresAhead(from location: CLLocation, features: [Feature], green: Feature, limit: Int = 3) -> [FeatureDistance] {
        let coord = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        if PolygonGeometry.contains(coord, in: green.polygon) { return [] }

        let greenCenter = green.center.clLocation
        let distToGreen = location.distance(from: greenCenter)

        return features.compactMap { feature in
            guard feature.type == .bunker || feature.type == .water else { return nil }

            let featureLocation = feature.center.clLocation
            let distToFeature = location.distance(from: featureLocation)
            let featureToGreen = featureLocation.distance(from: greenCenter)

            guard featureToGreen < distToGreen && distToFeature < distToGreen else { return nil }

            return FeatureDistance(
                feature: feature,
                distanceYards: Int(distToFeature * metersToYards)
            )
        }
        .sorted { $0.distanceYards < $1.distanceYards }
        .prefix(limit)
        .map { $0 }
    }
}
