import Foundation
import CourseDataSwift

extension CourseSelection {
    /// An 18-hole course with no map features, for tests that need a round but not its geometry.
    static let test = CourseSelection(
        course: Course(
            name: "Test Course",
            clubName: "Test Club",
            location: CourseLocation(address: "", city: "Denver", state: "CO", country: "US",
                                     coordinate: Coordinate(latitude: 39.0, longitude: -105.0)),
            subCourses: [
                SubCourse(name: "Front", holes: (1...9).map { Hole(number: $0, par: 4) }),
                SubCourse(name: "Back", holes: (10...18).map { Hole(number: $0, par: 4) })
            ]
        ),
        selectedSubCourseIndices: [0, 1]
    )
}

/// Three holes laid out in meters from hole 1's tee, for tests of the GPS path. Each hole has a
/// 10 m tee box, a 30 m green 300 m away, and a centerline between them. Hole 2's tee is 40 m
/// east of hole 1's green, and hole 3's tee 40 m east of hole 2's green.
enum PathCourse {
    static let baseLatitude = 40.0
    static let baseLongitude = -105.0

    static func coordinate(north: Double, east: Double) -> Coordinate {
        Coordinate(latitude: baseLatitude + north / LocalDistance.metersPerDegree,
                   longitude: baseLongitude + east / (LocalDistance.metersPerDegree * cos(baseLatitude * .pi / 180)))
    }

    static func square(north: Double, east: Double, half: Double) -> [Coordinate] {
        [coordinate(north: north - half, east: east - half), coordinate(north: north - half, east: east + half),
         coordinate(north: north + half, east: east + half), coordinate(north: north + half, east: east - half)]
    }

    /// Where each hole's tee and green centers are: (north, east).
    static let tees: [(north: Double, east: Double)] = [(0, 0), (300, 60), (300, 420)]
    static let greens: [(north: Double, east: Double)] = [(300, 0), (300, 360), (300, 720)]

    static let selection: CourseSelection = {
        var features: [Feature] = []
        var holes: [Hole] = []
        for index in 0..<3 {
            let tee = Feature(id: 100 + index, type: .tee, polygon: square(north: tees[index].north, east: tees[index].east, half: 5))
            let green = Feature(id: 200 + index, type: .green,
                                polygon: square(north: greens[index].north, east: greens[index].east, half: 15))
            features += [tee, green]
            holes.append(Hole(number: index + 1, par: 4, features: [green.id], tees: ["Blue": tee.id],
                              centerline: [coordinate(north: tees[index].north, east: tees[index].east),
                                           coordinate(north: greens[index].north, east: greens[index].east)]))
        }
        return CourseSelection(
            course: Course(name: "Path Course",
                           location: CourseLocation(address: "", city: "", state: "", country: "US",
                                                    coordinate: coordinate(north: 0, east: 0)),
                           features: features,
                           subCourses: [SubCourse(name: "Front", holes: holes)]),
            selectedSubCourseIndices: [0]
        )
    }()
}
