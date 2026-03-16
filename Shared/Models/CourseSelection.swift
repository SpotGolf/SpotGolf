import Foundation
import CourseData

struct CourseSelection: Codable, Equatable {
    let course: Course
    let selectedSubCourseIndices: [Int]

    var orderedHoles: [Hole] {
        selectedSubCourseIndices.flatMap { index in
            guard index >= 0, index < course.subCourses.count else { return [Hole]() }
            return course.subCourses[index].holes
        }
    }
}
