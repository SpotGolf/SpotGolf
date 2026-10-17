import Foundation
import CourseDataSwift

struct CourseSelection: Codable, Equatable, Sendable {
    let course: Course
    let selectedSubCourseIndices: [Int]
    /// The tee the player picked, from `teeNames`. Nil for rounds started before tees were picked.
    let teeName: String?
    /// A shotgun start: the 0-based place in nine order of the first hole played. Nil is hole 1,
    /// so selections from before shotgun starts read and write as they did.
    private let startHoleIndex: Int?

    init(course: Course, selectedSubCourseIndices: [Int], teeName: String? = nil, startHoleIndex: Int = 0) {
        self.course = course
        self.selectedSubCourseIndices = selectedSubCourseIndices
        self.teeName = teeName
        self.startHoleIndex = startHoleIndex == 0 ? nil : startHoleIndex
    }

    /// The same nines and starting hole with `tee` picked.
    func with(tee: String?) -> CourseSelection {
        CourseSelection(course: course, selectedSubCourseIndices: selectedSubCourseIndices, teeName: tee,
                        startHoleIndex: startIndex)
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

    /// Each hole in nine order with the nine it belongs to: each selected nine in the order
    /// chosen, and within a nine by hole number, whatever order the course data lists them in.
    private var nineOrderHoles: [(nine: String, hole: Hole)] {
        selectedSubCourseIndices.flatMap { index in
            guard index >= 0, index < course.subCourses.count else { return [(nine: String, hole: Hole)]() }
            let subCourse = course.subCourses[index]
            return subCourse.holes.sorted { $0.number < $1.number }.map { (nine: subCourse.name, hole: $0) }
        }
    }

    /// Each hole in playing order: nine order, starting at the starting hole and going round to
    /// the hole before it. Every playing-order list and lookup comes from this one, so hole
    /// indexes always agree. See plans/2026-10-17-shotgun-start.md.
    private var orderedNineHoles: [(nine: String, hole: Hole)] {
        let holes = nineOrderHoles
        let start = startIndex(count: holes.count)
        return Array(holes[start...] + holes[..<start])
    }

    /// The number of holes in the selected nines.
    var holeCount: Int {
        nineOrderHoles.count
    }

    /// The 0-based place in nine order of the first hole played: 0 unless a shotgun start.
    var startIndex: Int {
        startIndex(count: holeCount)
    }

    private func startIndex(count: Int) -> Int {
        guard let startHoleIndex, count > 0, startHoleIndex > 0, startHoleIndex < count else { return 0 }
        return startHoleIndex
    }

    /// The hole number the player sees for the hole at playing-order `index`: its place in nine
    /// order, 1-based. Past the last hole, or with no holes, it is `index + 1`.
    func holeNumber(at index: Int) -> Int {
        let count = holeCount
        guard index >= 0, index < count else { return index + 1 }
        return (index + startIndex) % count + 1
    }

    /// The playing-order index of hole `number` (1-based, nine order). The reverse of `holeNumber(at:)`.
    func playIndex(ofHoleNumber number: Int) -> Int {
        let count = holeCount
        guard number >= 1, number <= count else { return number - 1 }
        return (number - 1 - startIndex + count) % count
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
            teeName: teeName,
            startHoleIndex: startIndex
        )
    }
}
