import CourseDataSwift
import XCTest
@testable import SpotGolf

final class GreenHeatMapTests: XCTestCase {
    /// A 5 by 4 surface that rises 2 cm for each meter east and 1 cm for each meter south.
    private func tiltedSurface() -> ElevationSurface {
        var elevations: [Double?] = []
        for row in 0..<4 {
            for column in 0..<5 {
                elevations.append(100 + 0.02 * Double(column) - 0.01 * Double(row))
            }
        }
        return ElevationSurface(origin: Coordinate(lat: 39, lon: -105), columns: 5, elevations: elevations)
    }

    func testSlopeAndDownhillDirectionOfATiltedPlane() {
        let heatMap = GreenHeatMap(surface: tiltedSurface(), polygon: [Coordinate]())

        XCTAssertEqual(heatMap.cells.count, 20)
        let expectedSlope = (0.02 * 0.02 + 0.01 * 0.01).squareRoot() * 100
        for cell in heatMap.cells {
            XCTAssertEqual(cell.slopePercent, expectedSlope, accuracy: 0.001)
            // Downhill is west and north
            XCTAssertEqual(cell.downhillEast, -0.02 / (expectedSlope / 100), accuracy: 0.001)
            XCTAssertEqual(cell.downhillNorth, 0.01 / (expectedSlope / 100), accuracy: 0.001)
        }
    }

    func testCellWithNoNeighborOnAnAxisIsLeftOut() {
        // Row 0 has only its middle cell, so that cell has no east or west neighbor
        let surface = ElevationSurface(origin: Coordinate(lat: 39, lon: -105), columns: 3, elevations: [
            nil, 10, nil,
            10, 10, 10,
            10, 10, 10,
        ])

        let heatMap = GreenHeatMap(surface: surface, polygon: [Coordinate]())

        XCTAssertEqual(heatMap.cells.count, 6)
        XCTAssertFalse(heatMap.cells.contains { $0.row == 0 })
        XCTAssertTrue(heatMap.cells.allSatisfy { $0.slopePercent == 0 && $0.downhillEast == 0 && $0.downhillNorth == 0 })
    }

    func testOnlyCellsInsideTheOutlineAreOnTheGreen() {
        let all = GreenHeatMap(surface: tiltedSurface(), polygon: [Coordinate]())
        // Around the cells from (1, 1) to (3, 2)
        let outline = [
            all.coordinate(column: 0.5, row: 0.5), all.coordinate(column: 3.5, row: 0.5),
            all.coordinate(column: 3.5, row: 2.5), all.coordinate(column: 0.5, row: 2.5),
        ]

        let heatMap = GreenHeatMap(surface: tiltedSurface(), polygon: outline)

        XCTAssertFalse(all.cells.contains(where: \.isOnGreen))
        XCTAssertEqual(heatMap.cells.filter(\.isOnGreen).map(\.column), [1, 2, 3, 1, 2, 3])
        XCTAssertEqual(heatMap.cells.filter(\.isOnGreen).map(\.row), [1, 1, 1, 2, 2, 2])
    }

    func testCellsAreASpacingApart() {
        let heatMap = GreenHeatMap(surface: tiltedSurface(), polygon: [Coordinate]())

        let origin = heatMap.coordinate(column: 0, row: 0)
        let far = heatMap.coordinate(column: 3, row: 2)

        XCTAssertEqual(origin, Coordinate(lat: 39, lon: -105))
        XCTAssertEqual(LocalDistance.meters(fromLat: origin.lat, lon: origin.lon, toLat: far.lat, lon: origin.lon), 2, accuracy: 1e-6)
        XCTAssertEqual(LocalDistance.meters(fromLat: origin.lat, lon: origin.lon, toLat: origin.lat, lon: far.lon), 3, accuracy: 1e-6)
    }

    func testColorBlendsBetweenTheMiddlesOfTheBands() {
        let bands = GreenHeatMap.bands
        func assertClose(_ color: GreenHeatMap.BandColor, _ r: Double, _ g: Double, _ b: Double, line: UInt = #line) {
            XCTAssertEqual(color.red, r, accuracy: 1e-9, line: line)
            XCTAssertEqual(color.green, g, accuracy: 1e-9, line: line)
            XCTAssertEqual(color.blue, b, accuracy: 1e-9, line: line)
        }

        // Flat and very steep ground get the first and last color
        XCTAssertEqual(GreenHeatMap.color(forSlopePercent: 0), bands[0])
        XCTAssertEqual(GreenHeatMap.color(forSlopePercent: 12), bands[4])
        // The middle of a band is that band's color
        assertClose(GreenHeatMap.color(forSlopePercent: 2.5), bands[2].red, bands[2].green, bands[2].blue)
        // The edge between two bands is half of each
        assertClose(GreenHeatMap.color(forSlopePercent: 3),
                    (bands[2].red + bands[3].red) / 2, (bands[2].green + bands[3].green) / 2, (bands[2].blue + bands[3].blue) / 2)
    }

    func testSlopeGridFillsPositionsNextToCells() {
        // 7 wide and 3 tall, rising 1 cm for each meter east. The first three columns have no
        // elevation.
        var elevations: [Double?] = []
        for _ in 0..<3 {
            for column in 0..<7 {
                elevations.append(column < 3 ? nil : 10 + 0.01 * Double(column))
            }
        }
        let surface = ElevationSurface(origin: Coordinate(lat: 39, lon: -105), columns: 7, elevations: elevations)

        let heatMap = GreenHeatMap(surface: surface, polygon: [Coordinate]())
        let grid = heatMap.slopeGrid

        XCTAssertEqual(grid.count, 21)
        for row in 0..<3 {
            // No cell two columns out, then two filled columns, then the cells themselves
            XCTAssertNil(grid[row * 7])
            for column in 1..<7 {
                XCTAssertEqual(try XCTUnwrap(grid[row * 7 + column]), 1, accuracy: 1e-6, "column \(column), row \(row)")
            }
        }
    }

    func testImageHasOnePixelPerCell() throws {
        let image = try XCTUnwrap(GreenHeatMap(surface: tiltedSurface(), polygon: [Coordinate]()).makeImage())

        XCTAssertEqual(image.width, 5)
        XCTAssertEqual(image.height, 4)
        let empty = ElevationSurface(origin: Coordinate(lat: 39, lon: -105), columns: 0, elevations: [])
        XCTAssertNil(GreenHeatMap(surface: empty, polygon: [Coordinate]()).makeImage())
    }
}
