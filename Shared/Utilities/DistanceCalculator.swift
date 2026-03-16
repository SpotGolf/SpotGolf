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
        GreenDistances(
            front: Int(yards(from: location, to: green.front(vector: direction).clLocation)),
            middle: Int(yards(from: location, to: green.middle().clLocation)),
            back: Int(yards(from: location, to: green.back(vector: direction).clLocation))
        )
    }

    static func featuresAhead(from location: CLLocation, features: [Feature], green: Feature) -> [FeatureDistance] {
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
    }
}
