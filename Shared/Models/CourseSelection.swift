import Foundation
import CourseDataSwift

struct CourseSelection: Codable, Equatable, Sendable {
    let course: Course
    let selectedSubCourseIndices: [Int]
    /// The tee the player picked, from `teeNames`. Nil for rounds started before tees were picked.
    let teeName: String?

    init(course: Course, selectedSubCourseIndices: [Int], teeName: String? = nil) {
        self.course = course
        self.selectedSubCourseIndices = selectedSubCourseIndices
        self.teeName = teeName
    }

    /// The tees a player can pick: the course's tees, then its combo tees.
    var teeNames: [String] {
        course.tees.map(\.name) + course.comboTees.map(\.name)
    }

    /// The yards of `hole` from `tee`. A combo tee uses the tee the hole names for it.
    static func yards(of hole: Hole, tee: String) -> Int? {
        hole.yardages[tee] ?? hole.comboTees[tee].flatMap { hole.yardages[$0] }
    }

    /// The yards of the hole at `index` from the picked tee. Nil without a tee or its yards.
    func yards(holeIndex index: Int) -> Int? {
        let holes = orderedHoles
        guard let teeName, index >= 0, index < holes.count else { return nil }
        return Self.yards(of: holes[index], tee: teeName)
    }

    /// The color of `tee` as "#RRGGBB". A combo tee has the color of its first tee.
    func teeColor(_ tee: String) -> String {
        let name = course.comboTees.first { $0.name == tee }?.tees.first ?? tee
        return course.tees.first { $0.name == name }?.color ?? TeeDefinition.defaultColor(for: name)
    }

    /// Each hole in playing order with the nine it belongs to: each selected nine in the order
    /// chosen, and within a nine by hole number, whatever order the course data lists them in.
    /// Every playing-order list and lookup comes from this one, so hole indexes always agree.
    private var orderedNineHoles: [(nine: String, hole: Hole)] {
        selectedSubCourseIndices.flatMap { index in
            guard index >= 0, index < course.subCourses.count else { return [(nine: String, hole: Hole)]() }
            let subCourse = course.subCourses[index]
            return subCourse.holes.sorted { $0.number < $1.number }.map { (nine: subCourse.name, hole: $0) }
        }
    }

    /// The holes in playing order.
    var orderedHoles: [Hole] {
        orderedNineHoles.map(\.hole)
    }

    /// The nine's name and number of the hole at `index` in playing order, or nil past the last
    /// hole. The same hole on every phone, whichever nine a round starts on.
    func holeKey(at index: Int) -> (subCourse: String, number: Int)? {
        let holes = orderedNineHoles
        guard index >= 0, index < holes.count else { return nil }
        return (subCourse: holes[index].nine, number: holes[index].hole.number)
    }

    /// The playing-order index of a nine's hole, or nil when the round does not play it.
    func holeIndex(subCourse: String, number: Int) -> Int? {
        orderedNineHoles.firstIndex { $0.nine == subCourse && $0.hole.number == number }
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
            comboTees: course.comboTees,
            features: course.features.filter { usedFeatureIDs.contains($0.id) },
            subCourses: selectedSubCourses
        )
        return CourseSelection(
            course: trimmedCourse,
            selectedSubCourseIndices: Array(0..<selectedSubCourses.count),
            teeName: teeName
        )
    }
}
