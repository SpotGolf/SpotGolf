import CoreLocation

struct GreenDistances {
    let front: Int
    let middle: Int
    let back: Int
}

struct FeatureDistance {
    let feature: CourseFeature
    let distanceYards: Int
}

enum DistanceCalculator {
    private static let metersToYards = 1.09361

    /// Returns distance in yards between two locations
    static func yards(from a: CLLocation, to b: CLLocation) -> Double {
        a.distance(from: b) * metersToYards
    }

    /// Returns distance in yards between two ball marks
    static func yards(from a: BallMark, to b: BallMark) -> Double {
        yards(from: a.location, to: b.location)
    }

    /// Returns a formatted distance string in yards
    static func formattedYards(from a: CLLocation, to b: CLLocation) -> String {
        "\(Int(yards(from: a, to: b))) yds"
    }

    /// Returns a formatted distance string in yards between two ball marks
    static func formattedYards(from a: BallMark, to b: BallMark) -> String {
        formattedYards(from: a.location, to: b.location)
    }

    /// Returns distances in yards to the front, middle, and back of the green
    static func greenDistances(from location: CLLocation, green: CourseGreen) -> GreenDistances {
        GreenDistances(
            front: Int(yards(from: location, to: green.front.clLocation)),
            middle: Int(yards(from: location, to: green.middle.clLocation)),
            back: Int(yards(from: location, to: green.back.clLocation))
        )
    }

    /// Returns features that are ahead of the user (between user and green), sorted by distance.
    static func featuresAhead(from location: CLLocation, features: [CourseFeature], green: CourseGreen) -> [FeatureDistance] {
        let distToGreen = location.distance(from: green.middle.clLocation)

        return features.compactMap { feature in
            let featureLocation = feature.middle
            let distToFeature = location.distance(from: featureLocation)
            let featureToGreen = featureLocation.distance(from: green.middle.clLocation)

            // Feature is "ahead" if it's closer to the green than we are
            // and closer to us than the green is
            guard featureToGreen < distToGreen && distToFeature < distToGreen else { return nil }

            return FeatureDistance(
                feature: feature,
                distanceYards: Int(distToFeature * metersToYards)
            )
        }
        .sorted { $0.distanceYards < $1.distanceYards }
    }
}
