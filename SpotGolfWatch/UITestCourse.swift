import CourseDataSwift

extension CourseSelection {
    /// An 18-hole course with no map features, for watch UI tests that start a round without the phone.
    static let uiTestCourse = CourseSelection(
        course: Course(
            name: "UI Test Course",
            clubName: "UI Test Club",
            location: CourseLocation(address: "", city: "", state: "", country: "US",
                                     coordinate: Coordinate(latitude: 0, longitude: 0)),
            subCourses: [
                SubCourse(name: "Front", holes: (1...9).map { Hole(number: $0, par: 4) }),
                SubCourse(name: "Back", holes: (10...18).map { Hole(number: $0, par: 4) })
            ]
        ),
        selectedSubCourseIndices: [0, 1]
    )
}
