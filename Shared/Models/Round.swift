import Foundation
import CourseData

struct Round: Identifiable {
    let id: UUID
    let date: Date
    var holes: [RoundHole]
    var currentHoleIndex: Int
    var isActive: Bool
    var courseSelection: CourseSelection?

    static let maxHoles = 18

    init(id: UUID = UUID(), date: Date = Date(), holes: [RoundHole] = [RoundHole()],
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

    var displayTitle: String {
        let dateStr = date.formatted(date: .long, time: .omitted)
        if let name = courseSelection?.course.name {
            return "\(Self.shortenCourseName(name)) on \(dateStr)"
        }
        return dateStr
    }

    static func shortenCourseName(_ name: String) -> String {
        var s = name

        // Strip leading "The Club at " or "The "
        if s.lowercased().hasPrefix("the club at ") {
            s = String(s.dropFirst("the club at ".count))
        } else if s.lowercased().hasPrefix("the ") {
            s = String(s.dropFirst("the ".count))
        }

        // Replace trailing suffixes (case-insensitive, longest match first)
        let replacements: [(suffix: String, replacement: String)] = [
            ("country club", "CC"),
            ("golf course", "GC"),
            ("golf resort", "GC"),
            ("golf club", "GC"),
            ("resort", "Resort"),
        ]
        let lower = s.lowercased()
        for (suffix, replacement) in replacements {
            if lower.hasSuffix(suffix) {
                s = String(s.dropLast(suffix.count)) + replacement
                break
            }
        }

        return s.trimmingCharacters(in: .whitespaces)
    }

    var currentHole: RoundHole {
        holes[min(currentHoleIndex, holes.count - 1)]
    }

    var currentHoleNumber: Int {
        currentHoleIndex + 1
    }

    var currentCourseHole: Hole? {
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
        guard !hasMark(id: mark.id) else { return }
        let safeIndex = min(currentHoleIndex, holes.count - 1)
        holes[safeIndex].marks.append(mark)
    }

    mutating func addMark(_ mark: BallMark, toHoleIndex holeIndex: Int) {
        guard !hasMark(id: mark.id) else { return }
        while holes.count <= holeIndex && holes.count < Self.maxHoles {
            holes.append(RoundHole())
        }
        let safeIndex = min(holeIndex, holes.count - 1)
        holes[safeIndex].marks.append(mark)
    }

    func hasMark(id: UUID) -> Bool {
        holes.contains { $0.marks.contains { $0.id == id } }
    }

    /// Returns `true` if the hole index actually changed.
    @discardableResult
    mutating func nextHole() -> Bool {
        if currentHoleIndex == holes.count - 1 {
            guard holes.count < Self.maxHoles else { return false }
            holes.append(RoundHole())
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

        if let holes = try container.decodeIfPresent([RoundHole].self, forKey: .holes) {
            self.holes = holes.isEmpty ? [RoundHole()] : holes
            let decoded = try container.decodeIfPresent(Int.self, forKey: .currentHoleIndex) ?? 0
            self.currentHoleIndex = min(max(decoded, 0), self.holes.count - 1)
        } else {
            // Legacy format: flat marks array → single hole
            let marks = try container.decodeIfPresent([BallMark].self, forKey: .marks) ?? []
            self.holes = [RoundHole(marks: marks)]
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
