import Foundation

struct RoundHole: Identifiable, Codable, Equatable {
    let id: UUID
    var strokes: [Stroke]

    init(id: UUID = UUID(), strokes: [Stroke] = []) {
        self.id = id
        self.strokes = strokes
    }

    /// Every stroke counts, putts included.
    var strokeCount: Int {
        strokes.count
    }
}
