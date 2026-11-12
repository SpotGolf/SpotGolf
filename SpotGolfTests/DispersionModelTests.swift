import simd
import XCTest
@testable import SpotGolf

/// The shot model, against reference results from a Python version of it (400,000 shots). The
/// tolerances cover the chance in the shots. See plans/2026-11-11-shot-dispersion.md, section 8.
final class DispersionModelTests: XCTestCase {
    /// Broadie's middle group: σα 6.4°, three in four drives under 237 yards.
    private let mid = DispersionParams(sigmaAlphaDeg: 6.4, sigmaD: 0.10, d75: 237)
    /// Broadie's high group: σα 8.1°, three in four drives under 216 yards.
    private let high = DispersionParams(sigmaAlphaDeg: 8.1, sigmaD: 0.13, d75: 216)

    private struct Summary {
        let lateralSpread: Double
        let lateral: ClosedRange<Double>
        let downrange: ClosedRange<Double>
        let withinFairway: Double
        let lengthSkew: Double
        let meanX: Double
        let meanY: Double
        let medianY: Double

        init(_ shots: [SIMD2<Double>]) {
            let count = Double(shots.count)
            let xs = shots.map(\.x).sorted()
            let ys = shots.map(\.y).sorted()
            func quantile(_ sorted: [Double], _ chance: Double) -> Double { sorted[Int(chance * Double(sorted.count))] }
            meanX = xs.reduce(0, +) / count
            meanY = ys.reduce(0, +) / count
            medianY = quantile(ys, 0.5)
            let meanX = meanX
            lateralSpread = (xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) } / count).squareRoot()
            lateral = quantile(xs, 0.025)...quantile(xs, 0.975)
            downrange = quantile(ys, 0.025)...quantile(ys, 0.975)
            withinFairway = Double(xs.filter { abs($0) <= 17.5 }.count) / count
            let lengths = shots.map { simd_length($0) }
            let mean = lengths.reduce(0, +) / count
            let spread = (lengths.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / count).squareRoot()
            lengthSkew = lengths.reduce(0) { $0 + pow(($1 - mean) / spread, 3) } / count
        }
    }

    private func summary(_ params: DispersionParams) -> Summary {
        Summary(DispersionModel.sample(params, n: 200_000, seed: 11))
    }

    func testTheMiddleGroupMatchesTheReference() {
        let shots = summary(mid)

        XCTAssertEqual(shots.lateralSpread, 24.9, accuracy: 0.5)
        XCTAssertEqual(shots.lateral.lowerBound, -48.9, accuracy: 1)
        XCTAssertEqual(shots.lateral.upperBound, 48.9, accuracy: 1)
        XCTAssertEqual(shots.downrange.lowerBound, 159, accuracy: 3)
        XCTAssertEqual(shots.downrange.upperBound, 254, accuracy: 3)
        XCTAssertEqual(shots.withinFairway, 0.522, accuracy: 0.01)
        XCTAssertEqual(shots.lengthSkew, -1.37, accuracy: 0.15)
    }

    func testTheHighGroupMatchesTheReference() {
        let shots = summary(high)

        XCTAssertEqual(shots.lateralSpread, 28.2, accuracy: 0.5)
        XCTAssertEqual(shots.lateral.lowerBound, -55.7, accuracy: 1)
        XCTAssertEqual(shots.lateral.upperBound, 55.7, accuracy: 1)
        XCTAssertEqual(shots.downrange.lowerBound, 125, accuracy: 3)
        XCTAssertEqual(shots.downrange.upperBound, 235, accuracy: 3)
        XCTAssertEqual(shots.withinFairway, 0.472, accuracy: 0.01)
        XCTAssertEqual(shots.lengthSkew, -1.37, accuracy: 0.15)
    }

    func testTheSameSeedGivesTheSameShots() {
        XCTAssertEqual(DispersionModel.sample(mid, n: 1_000, seed: 3), DispersionModel.sample(mid, n: 1_000, seed: 3))
        XCTAssertNotEqual(DispersionModel.sample(mid, n: 1_000, seed: 3), DispersionModel.sample(mid, n: 1_000, seed: 4))
    }

    func testLeftAndRightBalance() {
        XCTAssertLessThan(abs(summary(mid).meanX), 0.5)
    }

    func testMishitsMakeATailOfShortShots() {
        let shots = summary(mid)

        XCTAssertGreaterThan(shots.medianY, shots.meanY, "The median sits past the mean")
        XCTAssertGreaterThan(shots.medianY - shots.downrange.lowerBound, shots.downrange.upperBound - shots.medianY,
                             "Farther short than long")
    }

    func testThreeInFourShotsAreUnderTheReportedDrive() {
        let lengths = DispersionModel.sample(mid, n: 100_000, seed: 5).map { simd_length($0) }.sorted()

        XCTAssertEqual(lengths[75_000], 237, accuracy: 0.5)
    }

    func testNoShotIsShorterThanAFifthOfTheFullDistance() {
        // From sand the distance spreads most
        let params = DispersionParams.forApproach(missAngle: 8.1, yards: 150, lie: .sand)
        let shortest = DispersionModel.sample(params, n: 100_000, seed: 2).map { simd_length($0) }.min() ?? 0

        XCTAssertGreaterThanOrEqual(shortest, 30 - 1e-9)
    }

    // MARK: - Spots

    func testThereAre121SpotsOfEqualChance() {
        let spots = DispersionModel.spots(mid)

        XCTAssertEqual(spots.distances.count * spots.angles.count, 121)
        XCTAssertEqual(spots.distances, spots.distances.sorted())
        XCTAssertEqual(spots.angles[5], 0, accuracy: 1e-9, "The middle angle is the aim")
        XCTAssertEqual(spots.angles[0], -spots.angles[10], accuracy: 1e-9)
        // One standard deviation is at a chance of 0.841, which is between steps 9 and 10
        XCTAssertLessThan(spots.angles[8], 6.4 * .pi / 180)
        XCTAssertGreaterThan(spots.angles[10], 6.4 * .pi / 180)
    }

    func testTheSpotsFollowTheShots() {
        let lengths = DispersionModel.sample(mid, n: 200_000, seed: 9).map { simd_length($0) }.sorted()
        let spots = DispersionModel.spots(mid)

        for (index, distance) in spots.distances.enumerated() {
            let chance = (Double(index) + 0.5) / 11
            XCTAssertEqual(distance, lengths[Int(chance * 200_000)], accuracy: 1, "Step \(index + 1)")
        }
    }

    // MARK: - The standard bell curve

    func testTheStandardBellCurve() {
        XCTAssertEqual(BellCurve.inverse(0.5), 0, accuracy: 1e-9)
        XCTAssertEqual(BellCurve.inverse(0.841344746), 1, accuracy: 1e-6)
        XCTAssertEqual(BellCurve.inverse(0.975), 1.959964, accuracy: 1e-6)
        XCTAssertEqual(BellCurve.inverse(0.01), -2.326348, accuracy: 1e-6, "The low tail")
        XCTAssertEqual(BellCurve.inverse(0.99), 2.326348, accuracy: 1e-6, "The high tail")
        XCTAssertEqual(BellCurve.chance(under: 1), 0.841344746, accuracy: 1e-9)
        XCTAssertEqual(BellCurve.chance(under: -1.959964), 0.025, accuracy: 1e-6)
    }

    // MARK: - By club, skill and lie

    func testTheDriverTakesThePlayersAngle() {
        let params = DispersionParams.forClub(isDriver: true, yards: 230, missAngle: 6.4, lie: .fairway)

        XCTAssertEqual(params, DispersionParams(sigmaAlphaDeg: 6.4, sigmaD: 0.10, dMu: 230))
    }

    func testOtherClubsTakeTheSolvedSpreads() {
        let params = DispersionParams.forClub(isDriver: false, yards: 145, missAngle: 6.4, lie: .fairway)

        XCTAssertEqual(params, DispersionParams(sigmaAlphaDeg: 5.49, sigmaD: 0.144, dMu: 145))
    }

    func testAClubUnder60YardsIsAShortShot() {
        let params = DispersionParams.forClub(isDriver: false, yards: 50, missAngle: 6.4, lie: .fairway)

        XCTAssertEqual(params, DispersionParams(sigmaAlphaDeg: 3.55, sigmaD: 0.198, dMu: 50))
        XCTAssertEqual(DispersionParams.forClub(isDriver: false, yards: 60, missAngle: 6.4, lie: .fairway).sigmaAlphaDeg, 5.49)
    }

    func testSkillRunsStraightBetweenGroupsAndStopsAtTheEnds() {
        XCTAssertEqual(DispersionParams.forDriver(missAngle: 5.9, yards: 230).sigmaD, 0.095, accuracy: 1e-9)
        XCTAssertEqual(DispersionParams.forDriver(missAngle: 7.25, yards: 230).sigmaD, 0.115, accuracy: 1e-9)
        XCTAssertEqual(DispersionParams.forDriver(missAngle: 4, yards: 230).sigmaD, 0.09)
        XCTAssertEqual(DispersionParams.forDriver(missAngle: 9, yards: 230).sigmaD, 0.13)
    }

    func testRoughAndSandSpreadTheDistanceMore() {
        func spread(_ lie: Lie) -> Double { DispersionParams.forApproach(missAngle: 6.4, yards: 145, lie: lie).sigmaD }

        XCTAssertEqual(spread(.fairway), 0.144, accuracy: 1e-9)
        XCTAssertEqual(spread(.green), 0.144, accuracy: 1e-9)
        XCTAssertEqual(spread(.rough), 0.144 * 1.25, accuracy: 1e-9)
        XCTAssertEqual(spread(.sand), 0.144 * 1.6, accuracy: 1e-9)
        XCTAssertEqual(DispersionParams.forApproach(missAngle: 6.4, yards: 145, lie: .sand).sigmaAlphaDeg, 5.49,
                       "The lie does not change the angle")
    }
}
