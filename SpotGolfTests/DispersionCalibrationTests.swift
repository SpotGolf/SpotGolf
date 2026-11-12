import simd
import XCTest
@testable import SpotGolf

/// Solves the spreads of every club but the driver again, and checks them against the stored
/// constants. The model is matched to Broadie's (2008, Table 2) median miss from the fairway.
/// See plans/2026-11-11-shot-dispersion.md, section 3.
final class DispersionCalibrationTests: XCTestCase {
    /// The median distance from a target `yards` away, as a share of `yards`, with an angle
    /// spread of `angle` radians and a distance spread of `ratio` times it.
    private func medianMiss(angle: Double, ratio: Double, yards: Double, lieSpread: Double = 1) -> Double {
        let params = DispersionParams(sigmaAlphaDeg: angle * 180 / .pi, sigmaD: ratio * angle * lieSpread, dMu: yards)
        let misses = DispersionModel.sample(params, n: 60_000, seed: 5).map { simd_length($0 - SIMD2(0, yards)) / yards }
        return misses.sorted()[misses.count / 2]
    }

    /// The angle spread, in radians, whose median miss is `target`, by halving.
    private func solve(target: Double, ratio: Double, yards: Double) -> Double {
        var (low, high) = (0.01, 0.3)
        for _ in 0..<20 {
            let middle = (low + high) / 2
            if medianMiss(angle: middle, ratio: ratio, yards: yards) < target { low = middle } else { high = middle }
        }
        return (low + high) / 2
    }

    func testTheApproachSpreadsMatchTheFairwayMisses() {
        let c = DispersionConstants.self
        for (group, target) in c.fairwayMisses.enumerated() {
            let angle = solve(target: target, ratio: c.approachDepthToLateral, yards: c.approachYards)

            XCTAssertEqual(c.approachAngles[group], angle * 180 / .pi, accuracy: 0.1, "Group \(group + 1)")
            XCTAssertEqual(c.approachDistanceSpreads[group], c.approachDepthToLateral * angle, accuracy: 0.004,
                           "Group \(group + 1)")
            // Not held to it: the rough's spread is an assumption
            let rough = medianMiss(angle: angle, ratio: c.approachDepthToLateral, yards: c.approachYards,
                                   lieSpread: c.roughSpread)
            print(String(format: "Group %d: median miss from the rough %.1f%%, Broadie %.1f%%", group + 1, rough * 100,
                         c.roughMisses[group] * 100))
        }
    }

    func testTheShortSpreadsMatchTheFairwayMisses() {
        let c = DispersionConstants.self
        for (group, target) in c.fairwayMisses.enumerated() {
            let angle = solve(target: target, ratio: c.shortDepthToLateral, yards: c.shortCalibrationYards)

            XCTAssertEqual(c.shortAngles[group], angle * 180 / .pi, accuracy: 0.1, "Group \(group + 1)")
            XCTAssertEqual(c.shortDistanceSpreads[group], c.shortDepthToLateral * angle, accuracy: 0.004, "Group \(group + 1)")
        }
    }

    /// Broadie and Ko's 80 and 100 golfers hit about 54% and 44% of 35-yard fairways. Logged, and
    /// held only to the right neighborhood.
    func testFairwaysHitAreNearBroadieAndKos() {
        for (score, published) in [(80.0, 0.54), (100.0, 0.44)] {
            let angle = MissAngle.degrees(averageScore: score)
            let params = DispersionParams(sigmaAlphaDeg: angle,
                                          sigmaD: DispersionParams.bySkill(DispersionConstants.driverDistanceSpreads, angle),
                                          d75: DispersionParams.bySkill(DispersionConstants.skillDrives, angle))
            let shots = DispersionModel.sample(params, n: 100_000, seed: 3)
            let hit = Double(shots.filter { abs($0.x) <= 17.5 }.count) / Double(shots.count)

            print(String(format: "Golfers averaging %.0f: %.1f%% of fairways hit, Broadie and Ko %.0f%%", score, hit * 100,
                         published * 100))
            XCTAssertEqual(hit, published, accuracy: 0.1)
        }
    }
}
