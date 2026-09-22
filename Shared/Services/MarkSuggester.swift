import Foundation
import CoreLocation
import CourseDataSwift

/// A place the player stayed for a while, offered on the map as a possible ball location.
struct MarkSuggestion: Identifiable, Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let duration: TimeInterval
    /// Set when the suggestion came from a synced `MissedMarkGuess`, so converting it can remove the guess.
    let guessID: UUID?

    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, timestamp: Date,
         duration: TimeInterval = 0, guessID: UUID? = nil) {
        self.id = id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.timestamp = timestamp
        self.duration = duration
        self.guessID = guessID
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Derives Mark suggestions from the GPS track of a round.
enum MarkSuggester {
    /// Points this close to where a dwell started are still part of the same dwell.
    static let dwellRadius: Double = 6 // meters
    /// A suggestion this close to an existing mark is dropped — the mark already covers it.
    static let nearMarkRadius: Double = 15
    /// A dwell this close to another suggestion is dropped as a duplicate.
    static let duplicateRadius: Double = 10
    /// Floor for `minDwell` — anything lower turns every pause into a suggestion.
    static let minimumDwell: TimeInterval = 10

    /// The track points that belong to one hole: each point is assigned to the hole
    /// whose features are nearest. Without a course selection every point is returned,
    /// because there is no geometry to slice by.
    static func holePoints(in points: [TrackPoint], holeIndex: Int,
                           courseSelection: CourseSelection?) -> [TrackPoint] {
        guard let selection = courseSelection else { return points }
        let holes = selection.orderedHoles
        guard holeIndex < holes.count else { return points }

        let course = selection.course
        let centersPerHole: [[Coordinate]] = holes.map { hole in
            course.features(for: hole).map(\.center)
        }

        return points.filter { point in
            var bestHole = -1
            var bestDistance = Double.greatestFiniteMagnitude
            for (index, centers) in centersPerHole.enumerated() {
                for center in centers {
                    let d = squaredMeters(fromLat: point.latitude, lon: point.longitude,
                                          toLat: center.latitude, lon: center.longitude)
                    if d < bestDistance {
                        bestDistance = d
                        bestHole = index
                    }
                }
            }
            return bestHole == holeIndex
        }
    }

    /// Places where the player stayed within `dwellRadius` for at least `minDwell`,
    /// plus any synced guesses. Suggestions near an existing mark or near an earlier
    /// suggestion are dropped. Results are in time order.
    static func suggestions(in points: [TrackPoint], minDwell: TimeInterval,
                            marks: [BallMark], guesses: [MissedMarkGuess] = []) -> [MarkSuggestion] {
        let minDwell = max(minDwell, minimumDwell)
        var result: [MarkSuggestion] = guesses
            .filter { !isNear($0.coordinate, marks: marks) }
            .map { MarkSuggestion(id: $0.id, coordinate: $0.coordinate,
                                  timestamp: $0.timestamp, guessID: $0.id) }

        if points.count >= 2 {
            var start = 0
            for end in 1...points.count {
                let closesCluster = end == points.count
                    || meters(fromLat: points[start].latitude, lon: points[start].longitude,
                              toLat: points[end].latitude, lon: points[end].longitude) > dwellRadius
                guard closesCluster else { continue }

                let cluster = points[start..<end]
                start = end
                let duration = cluster.last!.timestamp.timeIntervalSince(cluster.first!.timestamp)
                guard duration >= minDwell else { continue }

                let coordinate = CLLocationCoordinate2D(
                    latitude: cluster.map(\.latitude).reduce(0, +) / Double(cluster.count),
                    longitude: cluster.map(\.longitude).reduce(0, +) / Double(cluster.count)
                )
                let duplicate = result.contains {
                    meters(fromLat: coordinate.latitude, lon: coordinate.longitude,
                           toLat: $0.latitude, lon: $0.longitude) < duplicateRadius
                }
                if !duplicate && !isNear(coordinate, marks: marks) {
                    result.append(MarkSuggestion(coordinate: coordinate,
                                                 timestamp: cluster.first!.timestamp,
                                                 duration: duration))
                }
            }
        }

        return result.sorted { $0.timestamp < $1.timestamp }
    }

    private static func isNear(_ coordinate: CLLocationCoordinate2D, marks: [BallMark]) -> Bool {
        marks.contains {
            meters(fromLat: coordinate.latitude, lon: coordinate.longitude,
                   toLat: $0.coordinate.latitude, lon: $0.coordinate.longitude) < nearMarkRadius
        }
    }

    // Equirectangular approximation — plenty accurate over a golf hole and far
    // cheaper than CLLocation.distance for every point-to-feature pair.
    private static func meters(fromLat latA: Double, lon lonA: Double,
                               toLat latB: Double, lon lonB: Double) -> Double {
        squaredMeters(fromLat: latA, lon: lonA, toLat: latB, lon: lonB).squareRoot()
    }

    private static func squaredMeters(fromLat latA: Double, lon lonA: Double,
                                      toLat latB: Double, lon lonB: Double) -> Double {
        let metersPerDegree = 111_320.0
        let dLat = (latB - latA) * metersPerDegree
        let dLon = (lonB - lonA) * metersPerDegree * cos(latA * .pi / 180)
        return dLat * dLat + dLon * dLon
    }
}
