import simd
import XCTest
@testable import SpotGolf

/// The regions of a shot pattern. See plans/2026-11-11-shot-dispersion.md, section 8.
final class DispersionContoursTests: XCTestCase {
    private static let params = DispersionParams(sigmaAlphaDeg: 6.4, sigmaD: 0.10, d75: 237)
    /// Worked out once: 150,000 shots.
    private static let shape = DispersionContours.shape(of: params)

    func testEachRegionHoldsItsShareOfFreshShots() {
        let fresh = DispersionModel.sample(Self.params, n: 50_000, seed: 99)

        XCTAssertEqual(Self.shape.regions.map(\.share), [0.5, 0.8, 0.95])
        for region in Self.shape.regions {
            let held = Double(fresh.filter(region.contains).count) / Double(fresh.count)
            XCTAssertEqual(held, region.share, accuracy: 0.015, "The \(Int(region.share * 100))% region")
        }
    }

    func testTheRegionsAreNested() {
        let regions = Self.shape.regions

        XCTAssertTrue(regions[0].ring.allSatisfy(regions[1].contains), "50% inside 80%")
        XCTAssertTrue(regions[1].ring.allSatisfy(regions[2].contains), "80% inside 95%")
    }

    func testTheShapeIsATeardrop() throws {
        let outer = try XCTUnwrap(Self.shape.outer).ring
        let aim = Self.params.dMu
        let short = aim - (outer.map(\.y).min() ?? 0)
        let long = (outer.map(\.y).max() ?? 0) - aim

        XCTAssertGreaterThan(short, 1.5 * long, "The tail runs back toward the player")
        XCTAssertEqual(outer.map(\.x).min() ?? 0, -(outer.map(\.x).max() ?? 0), accuracy: 4, "Even left and right")
        XCTAssertLessThan(outer.count, 200, "Simplified")
    }

    func testTheSpreadsCoverNineteenShotsInTwenty() {
        XCTAssertEqual(Self.shape.lateral, 48.9, accuracy: 1)
        XCTAssertEqual(Self.shape.downrange.lowerBound, 159, accuracy: 3)
        XCTAssertEqual(Self.shape.downrange.upperBound, 254, accuracy: 3)
    }

    func testAScaledShapeIsThePatternAtAnotherDistance() throws {
        let scaled = Self.shape.scaled(by: 0.5)

        XCTAssertEqual(scaled.lateral, Self.shape.lateral / 2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(scaled.outer).ring[0], try XCTUnwrap(Self.shape.outer).ring[0] * 0.5)
    }

    func testTheAdviserKeepsAShapeByItsSpreads() async {
        let adviser = ClubAdviser()
        let first = await adviser.shape(of: DispersionParams(sigmaAlphaDeg: 5.49, sigmaD: 0.144, dMu: 145))
        let again = await adviser.shape(of: DispersionParams(sigmaAlphaDeg: 5.49, sigmaD: 0.144, dMu: 145))
        let longer = await adviser.shape(of: DispersionParams(sigmaAlphaDeg: 5.49, sigmaD: 0.144, dMu: 165))

        XCTAssertEqual(first, again)
        // The same spreads: the kept shape, scaled to the longer club
        XCTAssertEqual(longer.lateral, first.lateral * 165 / 145, accuracy: 1e-9)
        XCTAssertEqual(longer.outer?.ring.count, first.outer?.ring.count)
    }

    func testAShortShotsRegionsHoldTheirSharesToo() {
        // A 50-yard pitch: its pattern is a few yards wide
        let params = DispersionParams.forShort(missAngle: 6.4, yards: 50)
        let fresh = DispersionModel.sample(params, n: 50_000, seed: 99)

        for region in DispersionContours.shape(of: params).regions {
            let held = Double(fresh.filter(region.contains).count) / Double(fresh.count)
            XCTAssertEqual(held, region.share, accuracy: 0.015, "The \(Int(region.share * 100))% region")
        }
    }

    func testOutlinesKeepTheirCornersWhenSimplified() {
        // A 10 by 10 square with a point every yard
        let side = (0..<10).map(Double.init)
        let square = side.map { SIMD2($0, 0) } + side.map { SIMD2(10, $0) } + side.map { SIMD2(10 - $0, 10) }
            + side.map { SIMD2(0, 10 - $0) }

        XCTAssertEqual(DispersionContours.simplified(square, tolerance: 0.5).count, 4)
    }
}
