import Foundation
import CourseDataSwift

struct CourseSelection: Codable, Equatable {
    let course: Course
    let selectedSubCourseIndices: [Int]

    /// The holes in playing order: each selected nine in the order chosen, and within a nine by
    /// hole number, whatever order the course data lists them in.
    var orderedHoles: [Hole] {
        selectedSubCourseIndices.flatMap { index in
            guard index >= 0, index < course.subCourses.count else { return [Hole]() }
            return course.subCourses[index].holes.sorted { $0.number < $1.number }
        }
    }

    /// Returns a trimmed copy with only the selected sub-courses and their referenced features.
    var trimmed: CourseSelection {
        let selectedSubCourses = selectedSubCourseIndices.compactMap { index -> SubCourse? in
            guard index >= 0, index < course.subCourses.count else { return nil }
            return course.subCourses[index]
        }
        let usedFeatureIDs = Set(
            selectedSubCourses.flatMap { $0.holes.flatMap { $0.features } } +
            selectedSubCourses.flatMap { $0.holes.flatMap { $0.tees.values } }
        )
        let trimmedCourse = Course(
            id: course.id,
            name: course.name,
            clubName: course.clubName,
            golfCourseAPIIds: course.golfCourseAPIIds,
            location: course.location,
            tees: course.tees,
            features: course.features.filter { usedFeatureIDs.contains($0.id) },
            subCourses: selectedSubCourses
        )
        return CourseSelection(
            course: trimmedCourse,
            selectedSubCourseIndices: Array(0..<selectedSubCourses.count)
        )
    }
}
