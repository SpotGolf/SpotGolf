import CoreGraphics
import CourseDataSwift
import Foundation

/// The slope of a green, worked out from its elevation surface, for Green View's heat map.
/// The same figures and colors as CourseBuilder's heat map.
struct GreenHeatMap: Equatable {
    /// One square of the green's surface.
    struct Cell: Equatable {
        let column: Int
        let row: Int
        /// The steepness of the ground, as a percent grade.
        let slopePercent: Double
        /// The downhill direction as a unit vector, or zero where the ground is level.
        let downhillEast: Double
        let downhillNorth: Double
        /// Whether the center of the cell is inside the green's outline.
        let isOnGreen: Bool
    }

    struct BandColor: Equatable {
        let red: Double
        let green: Double
        let blue: Double
    }

    /// One color per percent of slope: under 1%, 1 to 2%, 2 to 3%, 3 to 4%, and 4% and over.
    /// Flat ground is bright green, and the color moves through yellow and orange to red as the
    /// ground gets steeper.
    static let bands: [BandColor] = [
        BandColor(red: 0x1e / 255.0, green: 0xe0 / 255.0, blue: 0x28 / 255.0),
        BandColor(red: 0xa8 / 255.0, green: 0xf0 / 255.0, blue: 0x00 / 255.0),
        BandColor(red: 0xf2 / 255.0, green: 0xf2 / 255.0, blue: 0x00 / 255.0),
        BandColor(red: 0xff / 255.0, green: 0x9a / 255.0, blue: 0x00 / 255.0),
        BandColor(red: 0xf5 / 255.0, green: 0x45 / 255.0, blue: 0x0f / 255.0),
    ]

    /// The color for a slope. Each band's color sits at the middle of its range (0.5%, 1.5%, and
    /// so on), and slopes in between get a blend of the two nearest colors. Slopes under 0.5% and
    /// over 4.5% get the first and last color.
    static func color(forSlopePercent slope: Double) -> BandColor {
        let position = min(max(slope - 0.5, 0), Double(bands.count - 1))
        let lower = min(Int(position), bands.count - 2)
        let fraction = position - Double(lower)
        let from = bands[lower], to = bands[lower + 1]
        return BandColor(red: from.red + (to.red - from.red) * fraction,
                         green: from.green + (to.green - from.green) * fraction,
                         blue: from.blue + (to.blue - from.blue) * fraction)
    }

    let origin: Coordinate
    /// Meters between the centers of neighboring cells.
    let spacing: Double
    let columns: Int
    let rows: Int
    /// Every cell whose slope can be worked out, row by row from south to north.
    let cells: [Cell]

    /// - Parameters:
    ///   - surface: The green's elevation surface.
    ///   - polygon: The green's outline.
    init(surface: ElevationSurface, polygon: some RandomAccessCollection<Coordinate>) {
        origin = surface.origin
        spacing = surface.spacing
        columns = surface.columns
        rows = surface.rows

        var cells: [Cell] = []
        for row in 0..<surface.rows {
            for column in 0..<surface.columns {
                guard let elevation = surface.elevation(column: column, row: row),
                      let east = Self.gradient(before: surface.elevation(column: column - 1, row: row), at: elevation,
                                               after: surface.elevation(column: column + 1, row: row),
                                               spacing: surface.spacing),
                      let north = Self.gradient(before: surface.elevation(column: column, row: row - 1), at: elevation,
                                                after: surface.elevation(column: column, row: row + 1),
                                                spacing: surface.spacing) else { continue }
                let steepness = (east * east + north * north).squareRoot()
                let center = Self.coordinate(origin: surface.origin, spacing: surface.spacing,
                                             column: Double(column), row: Double(row))
                cells.append(Cell(column: column, row: row, slopePercent: steepness * 100,
                                  downhillEast: steepness > 0 ? -east / steepness : 0,
                                  downhillNorth: steepness > 0 ? -north / steepness : 0,
                                  isOnGreen: PolygonGeometry.contains(center, in: polygon)))
            }
        }
        self.cells = cells
    }

    /// The rise per meter through a cell along one axis. Uses the cells on both sides where it
    /// can, and one side at the edge of the surface. Nil if the cell has no neighbor.
    private static func gradient(before: Double?, at elevation: Double, after: Double?, spacing: Double) -> Double? {
        switch (before, after) {
        case (let before?, let after?): (after - before) / (2 * spacing)
        case (let before?, nil): (elevation - before) / spacing
        case (nil, let after?): (after - elevation) / spacing
        case (nil, nil): nil
        }
    }

    /// The point `column` and `row` cells east and north of the origin. Whole numbers are cell
    /// centers, and half numbers are cell edges.
    func coordinate(column: Double, row: Double) -> Coordinate {
        Self.coordinate(origin: origin, spacing: spacing, column: column, row: row)
    }

    private static func coordinate(origin: Coordinate, spacing: Double, column: Double, row: Double) -> Coordinate {
        Coordinate(lat: origin.lat + row * spacing / LocalDistance.metersPerDegree,
                   lon: origin.lon + column * spacing / (LocalDistance.metersPerDegree * cos(origin.lat * .pi / 180)))
    }

    /// One slope per grid position, row by row from south to north, for drawing the heat map as
    /// a picture. A position with no cell takes the slope of the cells next to it, so the colors
    /// stay clean right up to the edge of the green. Nil further out.
    var slopeGrid: [Double?] {
        var grid = [Double?](repeating: nil, count: columns * rows)
        for cell in cells {
            grid[cell.row * columns + cell.column] = cell.slopePercent
        }
        for _ in 0..<2 {
            let known = grid
            for row in 0..<rows {
                for column in 0..<columns where known[row * columns + column] == nil {
                    var sum = 0.0, count = 0.0
                    for (dc, dr) in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)] {
                        let c = column + dc, r = row + dr
                        guard c >= 0, c < columns, r >= 0, r < rows, let slope = known[r * columns + c] else { continue }
                        sum += slope
                        count += 1
                    }
                    if count > 0 {
                        grid[row * columns + column] = sum / count
                    }
                }
            }
        }
        return grid
    }

    /// A picture of the slope colors with one pixel per cell and north at the top. Scaled up with
    /// blending, it makes the smooth heat map. Nil for a surface without cells.
    func makeImage() -> CGImage? {
        guard columns > 0, rows > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let grid = slopeGrid
        var pixels = [UInt8](repeating: 0, count: columns * rows * 4)
        for row in 0..<rows {
            for column in 0..<columns {
                guard let slope = grid[row * columns + column] else { continue }
                let color = Self.color(forSlopePercent: slope)
                // Image rows run from the top, and surface rows from the south
                let offset = ((rows - 1 - row) * columns + column) * 4
                pixels[offset] = UInt8((color.red * 255).rounded())
                pixels[offset + 1] = UInt8((color.green * 255).rounded())
                pixels[offset + 2] = UInt8((color.blue * 255).rounded())
                pixels[offset + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: columns, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: columns * 4,
                       space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
