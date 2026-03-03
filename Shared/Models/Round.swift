import Foundation

struct Round: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    var marks: [BallMark]
    var isActive: Bool

    init(id: UUID = UUID(), date: Date = Date(), marks: [BallMark] = [], isActive: Bool = true) {
        self.id = id
        self.date = date
        self.marks = marks
        self.isActive = isActive
    }

    var formattedDate: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    mutating func addMark(_ mark: BallMark) {
        marks.append(mark)
    }

    mutating func end() {
        isActive = false
    }
}
