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

    /// The hole's score: every stroke, putts included, plus a penalty stroke for each penalty or
    /// out of bounds stroke.
    var strokeCount: Int {
        strokes.reduce(0) { $0 + $1.score }
    }
}
