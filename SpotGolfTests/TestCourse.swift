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
