import Foundation

struct RoundHole: Identifiable, Codable, Equatable {
    let id: UUID
    var strokes: [Stroke]
    /// Saved by `RoundStore` when the strokes change. Nil with no strokes.
    var stats: HoleStats?

    init(id: UUID = UUID(), strokes: [Stroke] = [], stats: HoleStats? = nil) {
        self.id = id
        self.strokes = strokes
        self.stats = stats
    }

    /// Every stroke counts, putts included.
    var strokeCount: Int {
        strokes.count
    }
}
