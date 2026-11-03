import Foundation

/// The average strokes to hole out from a spot, by its lie and its distance to the pin: Broadie's
/// PGA Tour table from *Every Shot Counts*. See plans/2026-11-02-caddie-club-and-aim.md, section 3.
enum StrokesToHoleOut {
    private struct Row {
        let yards: Double
        let fairway: Double
        let rough: Double
        let sand: Double
    }

    private static let offGreen: [Row] = [
        Row(yards: 20, fairway: 2.40, rough: 2.59, sand: 2.53),
        Row(yards: 40, fairway: 2.60, rough: 2.78, sand: 2.82),
        Row(yards: 60, fairway: 2.70, rough: 2.91, sand: 3.15),
        Row(yards: 80, fairway: 2.75, rough: 2.96, sand: 3.24),
        Row(yards: 100, fairway: 2.80, rough: 3.02, sand: 3.23),
        Row(yards: 120, fairway: 2.85, rough: 3.08, sand: 3.21),
        Row(yards: 140, fairway: 2.91, rough: 3.15, sand: 3.22),
        Row(yards: 160, fairway: 2.98, rough: 3.23, sand: 3.28),
        Row(yards: 180, fairway: 3.08, rough: 3.31, sand: 3.40),
        Row(yards: 200, fairway: 3.19, rough: 3.42, sand: 3.55),
        Row(yards: 220, fairway: 3.32, rough: 3.53, sand: 3.70),
        Row(yards: 240, fairway: 3.45, rough: 3.64, sand: 3.84),
        Row(yards: 260, fairway: 3.58, rough: 3.74, sand: 3.93),
        Row(yards: 280, fairway: 3.69, rough: 3.83, sand: 4.00),
        Row(yards: 300, fairway: 3.78, rough: 3.90, sand: 4.04),
        Row(yards: 320, fairway: 3.84, rough: 3.95, sand: 4.12),
        Row(yards: 340, fairway: 3.88, rough: 4.02, sand: 4.26),
        Row(yards: 360, fairway: 3.95, rough: 4.11, sand: 4.41),
        Row(yards: 380, fairway: 4.03, rough: 4.21, sand: 4.55),
        Row(yards: 400, fairway: 4.11, rough: 4.30, sand: 4.69),
        Row(yards: 420, fairway: 4.15, rough: 4.34, sand: 4.73),
        Row(yards: 440, fairway: 4.20, rough: 4.39, sand: 4.78),
        Row(yards: 460, fairway: 4.29, rough: 4.48, sand: 4.87),
        Row(yards: 480, fairway: 4.40, rough: 4.59, sand: 4.98),
        Row(yards: 500, fairway: 4.53, rough: 4.72, sand: 5.11),
        Row(yards: 520, fairway: 4.66, rough: 4.85, sand: 5.24),
        Row(yards: 540, fairway: 4.78, rough: 4.97, sand: 5.36),
        Row(yards: 560, fairway: 4.86, rough: 5.05, sand: 5.44),
        Row(yards: 580, fairway: 4.91, rough: 5.10, sand: 5.49),
        Row(yards: 600, fairway: 4.94, rough: 5.13, sand: 5.52),
    ]

    /// Feet to the pin, and putts.
    private static let putts: [(x: Double, y: Double)] = [
        (1, 1.00), (2, 1.01), (3, 1.05), (4, 1.13), (5, 1.23), (6, 1.34), (7, 1.42), (8, 1.50), (10, 1.61),
        (15, 1.78), (20, 1.87), (25, 1.94), (30, 2.00), (40, 2.12), (50, 2.21), (60, 2.28), (90, 2.40), (100, 2.45),
    ]

    // Each lie's column on its own, made once: a club pick looks up tens of thousands of spots
    private static let fairway = offGreen.map(\.fairway)
    private static let rough = offGreen.map(\.rough)
    private static let sand = offGreen.map(\.sand)
    /// The off-green rows are every `rowStep` yards from the first.
    private static let firstRow = 20.0
    private static let rowStep = 20.0

    /// From `yards` to the pin in `lie`. From water it is a penalty stroke and a drop there, in
    /// the rough, so `yards` is from the drop spot.
    static func strokes(_ lie: Lie, yards: Double) -> Double {
        switch lie {
        case .green: putts(feet: yards * 3)
        case .fairway: offGreen(fairway, yards: yards)
        case .rough: offGreen(rough, yards: yards)
        case .sand: offGreen(sand, yards: yards)
        case .water: 1 + offGreen(rough, yards: yards)
        }
    }

    /// Straight-line between the two rows around `feet`, and the end row past either end.
    static func putts(feet: Double) -> Double {
        let rows = putts
        if feet <= rows[0].x { return rows[0].y }
        for index in 1..<rows.count where feet < rows[index].x {
            let (a, b) = (rows[index - 1], rows[index])
            return a.y + (b.y - a.y) * (feet - a.x) / (b.x - a.x)
        }
        return rows[rows.count - 1].y
    }

    /// Straight-line between the two rows around `yards`, and the end row past either end.
    private static func offGreen(_ column: [Double], yards: Double) -> Double {
        let position = (yards - firstRow) / rowStep
        if position <= 0 { return column[0] }
        if position >= Double(column.count - 1) { return column[column.count - 1] }
        let index = Int(position)
        return column[index] + (column[index + 1] - column[index]) * (position - Double(index))
    }
}
