import Foundation
import simd

/// A shot pattern's shape, in shot-local yards: the regions that hold the likeliest 50%, 80% and
/// 95% of shots, and how far 95% of shots spread. See plans/2026-11-11-shot-dispersion.md,
/// section 4.
struct DispersionShape: Equatable, Sendable {
    struct Region: Equatable, Sendable {
        /// The share of shots inside.
        let share: Double
        /// The outline, closed from its last point to its first.
        let ring: [SIMD2<Double>]

        /// By the even-odd rule.
        func contains(_ point: SIMD2<Double>) -> Bool {
            guard var previous = ring.last else { return false }
            var inside = false
            for current in ring {
                if (current.y > point.y) != (previous.y > point.y),
                   point.x < (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x {
                    inside.toggle()
                }
                previous = current
            }
            return inside
        }
    }

    /// Smallest share first.
    let regions: [Region]
    /// 95% of shots stop within this many yards left or right of the aim line.
    let lateral: Double
    /// 95% of shots stop between these yards along the aim line.
    let downrange: ClosedRange<Double>

    /// The largest region.
    var outer: Region? { regions.last }

    /// The shape of the same pattern at `factor` times the full distance.
    func scaled(by factor: Double) -> DispersionShape {
        DispersionShape(regions: regions.map { Region(share: $0.share, ring: $0.ring.map { $0 * factor }) },
                        lateral: lateral * factor,
                        downrange: (downrange.lowerBound * factor)...(downrange.upperBound * factor))
    }
}

/// The shots a shape is worked out from, at a full distance of 1: a pattern's shots at any full
/// distance are these times it, so one set serves every club with the same spreads.
struct DispersionShots: Sendable {
    let shots: [SIMD2<Double>]
    /// Each shot's yards right of the aim line, and along it, smallest first.
    let sortedX: [Double]
    let sortedY: [Double]

    init(sigmaAlphaDeg: Double, sigmaD: Double, n: Int = DispersionConstants.shapeShots,
         seed: UInt64 = DispersionConstants.shapeSeed) {
        shots = DispersionModel.sample(DispersionParams(sigmaAlphaDeg: sigmaAlphaDeg, sigmaD: sigmaD, dMu: 1), n: n, seed: seed)
        sortedX = shots.map(\.x).sorted()
        sortedY = shots.map(\.y).sorted()
    }
}

/// Works a pattern's shape out from its shots: they are counted on a grid of 1-yard squares, the
/// counts are blurred, and each region is the outline around the densest squares that together
/// hold its share of the shots.
enum DispersionContours {
    static func shape(of params: DispersionParams) -> DispersionShape {
        shape(of: DispersionShots(sigmaAlphaDeg: params.sigmaAlphaDeg, sigmaD: params.sigmaD), dMu: params.dMu)
    }

    /// The shape of `unit`'s pattern at a full distance of `dMu` yards. A pattern grows evenly
    /// with its full distance, so the shape is worked out at `DispersionConstants.shapeYards`,
    /// where the grid's squares are a yard, and scaled: a wedge's small pattern gets squares as
    /// fine for its size as a driver's.
    static func shape(of unit: DispersionShots, dMu: Double) -> DispersionShape {
        shape(of: unit, at: DispersionConstants.shapeYards).scaled(by: dMu / DispersionConstants.shapeYards)
    }

    private static func shape(of unit: DispersionShots, at dMu: Double,
                              shares: [Double] = DispersionConstants.regionShares) -> DispersionShape {
        guard !unit.shots.isEmpty else { return DispersionShape(regions: [], lateral: 0, downrange: 0...0) }
        func quantile(_ sorted: [Double], _ chance: Double) -> Double {
            dMu * sorted[min(sorted.count - 1, max(0, Int((chance * Double(sorted.count)).rounded(.down))))]
        }
        let (xs, ys) = (unit.sortedX, unit.sortedY)

        // The grid covers all but the outermost 1 in 1,000 shots each way, with room around them
        // for the blur to fade to nothing, so every outline closes
        let size = DispersionConstants.gridYards
        let blur = DispersionConstants.blurSquares
        let reach = Int((3 * blur).rounded(.up))
        let margin = reach + 2
        let (lowX, highX) = (quantile(xs, 0.001), quantile(xs, 0.999))
        let (lowY, highY) = (quantile(ys, 0.001), quantile(ys, 0.999))
        let originX = (lowX / size).rounded(.down) * size - Double(margin) * size
        let originY = (lowY / size).rounded(.down) * size - Double(margin) * size
        let width = Int(((highX - originX) / size).rounded(.up)) + margin + 1
        let height = Int(((highY - originY) / size).rounded(.up)) + margin + 1

        var counts = [Double](repeating: 0, count: width * height)
        for unitShot in unit.shots {
            let shot = unitShot * dMu
            guard shot.y >= lowY, shot.y <= highY else { continue }
            let row = Int((shot.y - originY) / size)
            // Left and right are equally likely, so each shot counts as half of itself and half
            // of its mirror image: twice the shots for the outlines to settle on
            for x in [shot.x, -shot.x] where x >= lowX && x <= highX {
                counts[row * width + Int((x - originX) / size)] += 0.5
            }
        }
        let density = blurred(counts, width: width, height: height, sigma: blur, reach: reach)

        // Each square's value sits at its middle
        let grid = Grid(values: density, width: width, height: height, origin: SIMD2(originX + size / 2, originY + size / 2),
                        size: size)
        let levels = levels(density, shares: shares, total: Double(unit.shots.count))
        let regions = zip(shares, levels).compactMap { share, level -> DispersionShape.Region? in
            guard let ring = largestRing(grid, level: level) else { return nil }
            return DispersionShape.Region(share: share,
                                          ring: rounded(simplified(ring, tolerance: DispersionConstants.outlineYards)))
        }
        return DispersionShape(regions: regions, lateral: (quantile(xs, 0.975) - quantile(xs, 0.025)) / 2,
                               downrange: quantile(ys, 0.025)...quantile(ys, 0.975))
    }

    // MARK: - Density

    /// A bell-curve blur, across and then up.
    private static func blurred(_ values: [Double], width: Int, height: Int, sigma: Double, reach: Int) -> [Double] {
        var kernel = (-reach...reach).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let sum = kernel.reduce(0, +)
        kernel = kernel.map { $0 / sum }
        var across = [Double](repeating: 0, count: values.count)
        for row in 0..<height {
            for column in 0..<width {
                var total = 0.0
                for offset in max(-reach, -column)...min(reach, width - 1 - column) {
                    total += values[row * width + column + offset] * kernel[offset + reach]
                }
                across[row * width + column] = total
            }
        }
        var result = [Double](repeating: 0, count: values.count)
        for row in 0..<height {
            for column in 0..<width {
                var total = 0.0
                for offset in max(-reach, -row)...min(reach, height - 1 - row) {
                    total += across[(row + offset) * width + column] * kernel[offset + reach]
                }
                result[row * width + column] = total
            }
        }
        return result
    }

    /// For each share, the density that the densest squares holding that share of `total` shots
    /// are all above.
    private static func levels(_ density: [Double], shares: [Double], total: Double) -> [Double] {
        let sorted = density.filter { $0 > 0 }.sorted(by: >)
        return shares.map { share in
            var held = 0.0
            for value in sorted {
                held += value
                if held >= share * total { return value }
            }
            return sorted.last ?? 0
        }
    }

    // MARK: - Outlines

    private struct Grid {
        let values: [Double]
        let width: Int
        let height: Int
        /// Where the first value sits, and the gap between values, in yards.
        let origin: SIMD2<Double>
        let size: Double

        func value(_ column: Int, _ row: Int) -> Double { values[row * width + column] }
    }

    /// The outline around the values above `level` that takes in the most ground, by marching
    /// squares. Each outline point sits on the line between two neighboring values, one above
    /// the level and one not; the lines are numbered so that the pieces can be joined up.
    private static func largestRing(_ grid: Grid, level: Double) -> [SIMD2<Double>]? {
        let (width, height) = (grid.width, grid.height)
        // The line from a value to the next one across, and to the next one up
        func across(_ column: Int, _ row: Int) -> Int { 2 * (row * width + column) }
        func up(_ column: Int, _ row: Int) -> Int { 2 * (row * width + column) + 1 }
        var neighbors = [Int](repeating: -1, count: 4 * width * height)
        func join(_ a: Int, _ b: Int) {
            neighbors[2 * a + (neighbors[2 * a] < 0 ? 0 : 1)] = b
            neighbors[2 * b + (neighbors[2 * b] < 0 ? 0 : 1)] = a
        }
        for row in 0..<(height - 1) {
            for column in 0..<(width - 1) {
                let a = grid.value(column, row), b = grid.value(column + 1, row)
                let c = grid.value(column + 1, row + 1), d = grid.value(column, row + 1)
                let kind = (a > level ? 1 : 0) | (b > level ? 2 : 0) | (c > level ? 4 : 0) | (d > level ? 8 : 0)
                guard kind != 0, kind != 15 else { continue }
                let (bottom, right) = (across(column, row), up(column + 1, row))
                let (top, left) = (across(column, row + 1), up(column, row))
                switch kind {
                case 1, 14: join(left, bottom)
                case 2, 13: join(bottom, right)
                case 3, 12: join(left, right)
                case 4, 11: join(right, top)
                case 6, 9: join(bottom, top)
                case 7, 8: join(left, top)
                default:
                    // Opposite corners above the level: the middle says which pair is joined
                    let middleAbove = (a + b + c + d) / 4 > level
                    if (kind == 5) == middleAbove {
                        join(bottom, right)
                        join(left, top)
                    } else {
                        join(left, bottom)
                        join(right, top)
                    }
                }
            }
        }

        func point(_ line: Int) -> SIMD2<Double> {
            let (column, row) = ((line / 2) % width, (line / 2) / width)
            let isUp = line % 2 == 1
            let from = grid.value(column, row)
            let to = isUp ? grid.value(column, row + 1) : grid.value(column + 1, row)
            let share = to == from ? 0.5 : (level - from) / (to - from)
            let offset = isUp ? SIMD2(0, share) : SIMD2(share, 0)
            return grid.origin + (SIMD2(Double(column), Double(row)) + offset) * grid.size
        }

        var visited = [Bool](repeating: false, count: 2 * width * height)
        var best: [SIMD2<Double>]?
        var bestArea = 0.0
        for start in 0..<(2 * width * height) where !visited[start] && neighbors[2 * start] >= 0 {
            var ring: [SIMD2<Double>] = []
            var (previous, current) = (-1, start)
            var closed = false
            while current >= 0, !visited[current] {
                visited[current] = true
                ring.append(point(current))
                let (first, second) = (neighbors[2 * current], neighbors[2 * current + 1])
                let next = first != previous ? first : second
                previous = current
                current = next
                closed = current == start
            }
            let area = abs(signedArea(ring))
            if closed, ring.count >= 3, area > bestArea {
                best = ring
                bestArea = area
            }
        }
        return best
    }

    private static func signedArea(_ ring: [SIMD2<Double>]) -> Double {
        guard var previous = ring.last else { return 0 }
        var total = 0.0
        for current in ring {
            total += previous.x * current.y - current.x * previous.y
            previous = current
        }
        return total / 2
    }

    /// The ring with the points dropped that are within `tolerance` of the line through the
    /// points kept, by Douglas–Peucker on its two halves.
    static func simplified(_ ring: [SIMD2<Double>], tolerance: Double) -> [SIMD2<Double>] {
        guard ring.count > 4 else { return ring }
        // Halved at the first point and the point farthest from it
        let far = ring.indices.max { simd_distance_squared(ring[$0], ring[0]) < simd_distance_squared(ring[$1], ring[0]) } ?? 0
        guard far > 0 else { return ring }
        let first = simplified(line: Array(ring[0...far]), tolerance: tolerance)
        let second = simplified(line: Array(ring[far...]) + [ring[0]], tolerance: tolerance)
        return Array(first.dropLast()) + Array(second.dropLast())
    }

    /// The ring with each corner cut, by one pass of Chaikin's method: every side gives the
    /// points a quarter and three quarters of the way along it.
    static func rounded(_ ring: [SIMD2<Double>]) -> [SIMD2<Double>] {
        guard ring.count >= 3 else { return ring }
        return ring.indices.flatMap { index -> [SIMD2<Double>] in
            let (from, to) = (ring[index], ring[(index + 1) % ring.count])
            return [from * 0.75 + to * 0.25, from * 0.25 + to * 0.75]
        }
    }

    private static func simplified(line: [SIMD2<Double>], tolerance: Double) -> [SIMD2<Double>] {
        guard line.count > 2 else { return line }
        var keep = [Bool](repeating: false, count: line.count)
        keep[0] = true
        keep[line.count - 1] = true
        var spans = [(0, line.count - 1)]
        while let (from, to) = spans.popLast() {
            guard to > from + 1 else { continue }
            let (a, b) = (line[from], line[to])
            let along = b - a
            let length = simd_length(along)
            var (farthest, gap) = (from, 0.0)
            for index in (from + 1)..<to {
                let offset = line[index] - a
                let distance = length > 0 ? abs(along.x * offset.y - along.y * offset.x) / length : simd_length(offset)
                if distance > gap {
                    (farthest, gap) = (index, distance)
                }
            }
            if gap > tolerance {
                keep[farthest] = true
                spans.append((from, farthest))
                spans.append((farthest, to))
            }
        }
        return line.indices.filter { keep[$0] }.map { line[$0] }
    }
}
