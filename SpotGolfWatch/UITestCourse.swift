import CourseDataSwift

extension CourseSelection {
    /// An 18-hole course with no map features, for watch UI tests that start a round without the phone.
    /// Each nine numbers its holes 1 to 9, as real course data does; the round numbers them 1 to 18.
    static let uiTestCourse = CourseSelection(
        course: Course(
            name: "UI Test Course",
            clubName: "UI Test Club",
            location: CourseLocation(address: "", city: "", state: "", country: "US",
                                     coordinate: Coordinate(lat: 0, lon: 0)),
            subCourses: [
                SubCourse(name: "Front", holes: (1...9).map { Hole(number: $0, par: 4) }),
                SubCourse(name: "Back", holes: (1...9).map { Hole(number: $0, par: 4) })
            ]
        ),
        selectedSubCourseIndices: [0, 1]
    )
}
