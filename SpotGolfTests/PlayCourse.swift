import CoreLocation
import CourseDataSwift
@testable import SpotGolf

/// Made-up holes laid out in meters from hole 1's tee, as `PathCourse` does, for tests of the
/// Caddie's club and aim. Hole 1 has a 30 m square green and whatever features a test gives it;
/// hole 2 is beside it with features of its own.
enum PlayCourse {
    /// A rectangle of meters north and east of hole 1's tee.
    static func rectangle(north: ClosedRange<Double>, east: ClosedRange<Double>) -> [Coordinate] {
        [PathCourse.coordinate(north: north.lowerBound, east: east.lowerBound),
         PathCourse.coordinate(north: north.lowerBound, east: east.upperBound),
         PathCourse.coordinate(north: north.upperBound, east: east.upperBound),
         PathCourse.coordinate(north: north.upperBound, east: east.lowerBound)]
    }

    static func point(north: Double, east: Double = 0) -> CLLocationCoordinate2D {
        PathCourse.coordinate(north: north, east: east).clCoordinate
    }

    /// The plane the tests measure in: meters east (`x`) and north (`y`) of hole 1's tee.
    static let plane = GroundPlane(origin: PathCourse.coordinate(north: 0, east: 0))

    /// Hole 1, with its green centered `greenNorth` meters north of the tee, `features` and
    /// `centerline`.
    /// Hole 2 has `otherHole`, and a green of its own 200 m east.
    static func selection(greenNorth: Double, features: [(FeatureType, [Coordinate])] = [],
                          otherHole: [(FeatureType, [Coordinate])] = [], centerline: [Coordinate]? = nil) -> CourseSelection {
        var all: [Feature] = []
        func add(_ type: FeatureType, _ polygon: [Coordinate]) -> Int {
            let feature = Feature(id: all.count + 1, type: type, polygon: CoordinatePath(polygon))
            all.append(feature)
            return feature.id
        }
        let holeOne = [add(.green, PathCourse.square(north: greenNorth, east: 0, half: 15))]
            + features.map { add($0.0, $0.1) }
        let centerlineID = centerline.map { add(.centerline, $0) }
        let holeTwo = [add(.green, PathCourse.square(north: greenNorth, east: 200, half: 15))]
            + otherHole.map { add($0.0, $0.1) }
        return CourseSelection(
            course: Course(name: "Play Course",
                           location: CourseLocation(address: "", city: "", state: "", country: "US",
                                                    coordinate: PathCourse.coordinate(north: 0, east: 0)),
                           features: all,
                           subCourses: [SubCourse(name: "Front", holes: [Hole(number: 1, par: 4, features: holeOne, centerline: centerlineID),
                                                                       Hole(number: 2, par: 4, features: holeTwo)])]),
            selectedSubCourseIndices: [0])
    }

    /// Hole 1's lies, measured in `plane`.
    static func lies(_ selection: CourseSelection) -> LieGrid {
        LieGrid(course: selection.course, hole: selection.orderedHoles[0], plane: plane)
    }
}
