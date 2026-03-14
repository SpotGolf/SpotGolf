import Foundation

struct Round: Identifiable {
    let id: UUID
    let date: Date
    var holes: [Hole]
    var currentHoleIndex: Int
    var isActive: Bool
    var courseSelection: CourseSelection?

    init(id: UUID = UUID(), date: Date = Date(), holes: [Hole] = [Hole()],
         currentHoleIndex: Int = 0, isActive: Bool = true, courseSelection: CourseSelection? = nil) {
        self.id = id
        self.date = date
        self.holes = holes
        self.currentHoleIndex = currentHoleIndex
        self.isActive = isActive
        self.courseSelection = courseSelection
    }

    var formattedDate: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    var currentHole: Hole {
        holes[min(currentHoleIndex, holes.count - 1)]
    }

    var currentHoleNumber: Int {
        currentHoleIndex + 1
    }

    var currentCourseHole: CourseHole? {
        guard let selection = courseSelection else { return nil }
        let orderedHoles = selection.orderedHoles
        guard currentHoleIndex < orderedHoles.count else { return nil }
        return orderedHoles[currentHoleIndex]
    }

    /// Marks for the current hole — preserves existing call sites.
    var marks: [BallMark] {
        holes[min(currentHoleIndex, holes.count - 1)].marks
    }

    /// All marks across all holes.
    var allMarks: [BallMark] {
        holes.flatMap { $0.marks }
    }

    mutating func addMark(_ mark: BallMark) {
        let safeIndex = min(currentHoleIndex, holes.count - 1)
        holes[safeIndex].marks.append(mark)
    }

    mutating func addMark(_ mark: BallMark, toHoleIndex holeIndex: Int) {
        while holes.count <= holeIndex && holes.count < 18 {
            holes.append(Hole())
        }
        let safeIndex = min(holeIndex, holes.count - 1)
        holes[safeIndex].marks.append(mark)
    }

    /// Returns `true` if the hole index actually changed.
    @discardableResult
    mutating func nextHole() -> Bool {
        if currentHoleIndex == holes.count - 1 {
            guard holes.count < 18 else { return false }
            holes.append(Hole())
        }
        currentHoleIndex += 1
        return true
    }

    /// Returns `true` if the hole index actually changed.
    @discardableResult
    mutating func previousHole() -> Bool {
        guard currentHoleIndex > 0 else { return false }
        currentHoleIndex -= 1
        return true
    }

    mutating func end() {
        // Trim trailing empty holes
        while holes.count > 1 && holes.last!.marks.isEmpty {
            holes.removeLast()
        }
        currentHoleIndex = min(currentHoleIndex, holes.count - 1)
        isActive = false
    }

    /// Find which hole contains a given mark by ID.
    func holeIndex(containing markID: UUID) -> Int? {
        holes.firstIndex(where: { hole in
            hole.marks.contains(where: { $0.id == markID })
        })
    }
}

// MARK: - Equatable & Codable

extension Round: Equatable {}

extension Round: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, date, holes, currentHoleIndex, isActive, courseSelection
        case marks // legacy key
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        isActive = try container.decode(Bool.self, forKey: .isActive)

        if let holes = try container.decodeIfPresent([Hole].self, forKey: .holes) {
            self.holes = holes.isEmpty ? [Hole()] : holes
            let decoded = try container.decodeIfPresent(Int.self, forKey: .currentHoleIndex) ?? 0
            self.currentHoleIndex = min(max(decoded, 0), self.holes.count - 1)
        } else {
            // Legacy format: flat marks array → single hole
            let marks = try container.decodeIfPresent([BallMark].self, forKey: .marks) ?? []
            self.holes = [Hole(marks: marks)]
            self.currentHoleIndex = 0
        }
        self.courseSelection = try container.decodeIfPresent(CourseSelection.self, forKey: .courseSelection)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(holes, forKey: .holes)
        try container.encode(currentHoleIndex, forKey: .currentHoleIndex)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(courseSelection, forKey: .courseSelection)
    }
}
