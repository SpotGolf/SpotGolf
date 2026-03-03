import Foundation

struct Hole: Identifiable, Codable, Equatable {
    let id: UUID
    var marks: [BallMark]

    init(id: UUID = UUID(), marks: [BallMark] = []) {
        self.id = id
        self.marks = marks
    }

    var strokeCount: Int {
        max(marks.count - 1, 0)
    }
}
