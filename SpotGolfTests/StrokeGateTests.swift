import XCTest
@testable import SpotGolf

final class StrokeGateTests: XCTestCase {

    /// 200 Hz motion of a putting stroke: still at address, a `backswing` in degrees about z
    /// over 0.5 s, then forward through the address angle at `contactAt`, plus `noise` rad/s.
    /// Gravity turns with the wrist.
    static func stroke(contactAt: Double, seconds: Double, backswing: Double = 12, still: Double = 0) -> [StrokeGate.Sample] {
        let angle = backswing * .pi / 180
        let backStart = contactAt - 0.8, top = contactAt - 0.3
        let back = angle / (top - backStart), forward = angle / (contactAt - top)
        var state: UInt32 = 7
        func noise() -> Double {
            state = state &* 1_664_525 &+ 1_013_904_223
            return (Double(state) / Double(UInt32.max) - 0.5) * 2 * still
        }
        return (0..<Int(seconds * 200)).map { k in
            let t = Double(k) / 200
            let rate: Double, turned: Double
            switch t {
            case ..<backStart: (rate, turned) = (0, 0)
            case ..<top: (rate, turned) = (-back, -back * (t - backStart))
            default: (rate, turned) = (forward, -angle + forward * (t - top))
            }
            let gravity = SIMD3(sin(turned) * 0.3, 0, -1.0)
            return StrokeGate.Sample(time: t, rotation: SIMD3(noise(), noise(), rate + noise()), gravity: gravity)
        }
    }

    private func features(_ samples: [StrokeGate.Sample], at time: Double) -> StrokeGate.Features? {
        var gate = StrokeGate(keep: 10)
        // A second at a time, like the watch's batches
        for start in stride(from: 0, to: samples.count, by: 200) {
            gate.add(Array(samples[start..<min(start + 200, samples.count)]))
        }
        XCTAssertTrue(gate.isComplete(at: time))
        return gate.features(at: time)
    }

    func testPuttPasses() throws {
        let found = try XCTUnwrap(features(Self.stroke(contactAt: 8, seconds: 10), at: 8))

        XCTAssertTrue(found.passes)
        XCTAssertEqual(found.still, 0, accuracy: 0.001)
        XCTAssertEqual(found.backswing, 12, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(found.returnOffset), 0, accuracy: 0.02)
        XCTAssertLessThan(found.tilt, 1)
    }

    /// The same stroke with the watch worn any way round gives the same answer.
    func testWatchOrientationDoesNotMatter() throws {
        let samples = Self.stroke(contactAt: 8, seconds: 10)
        let reference = try XCTUnwrap(features(samples, at: 8))
        // A rotation of 1 rad about an odd axis, and a mirror for the other wrist
        let axis = SIMD3(0.3, -0.5, 0.81) / (SIMD3(0.3, -0.5, 0.81) * SIMD3(0.3, -0.5, 0.81)).sum().squareRoot()
        func rotate(_ v: SIMD3<Double>) -> SIMD3<Double> {
            let c = cos(1.0), s = sin(1.0)
            let cross = SIMD3(axis.y * v.z - axis.z * v.y, axis.z * v.x - axis.x * v.z, axis.x * v.y - axis.y * v.x)
            return v * c + cross * s + axis * ((axis * v).sum() * (1 - c))
        }
        let rotated = samples.map { StrokeGate.Sample(time: $0.time, rotation: rotate($0.rotation), gravity: rotate($0.gravity)) }
        let mirrored = samples.map { s in
            // A mirror flips rotation's handedness: a reflected axial vector is negated
            StrokeGate.Sample(time: s.time, rotation: -SIMD3(-s.rotation.x, s.rotation.y, s.rotation.z),
                              gravity: SIMD3(-s.gravity.x, s.gravity.y, s.gravity.z))
        }
        for other in [rotated, mirrored] {
            let found = try XCTUnwrap(features(other, at: 8))
            XCTAssertEqual(found.still, reference.still, accuracy: 1e-6)
            XCTAssertEqual(found.tilt, reference.tilt, accuracy: 1e-6)
            XCTAssertEqual(found.backswing, reference.backswing, accuracy: 1e-6)
            XCTAssertEqual(try XCTUnwrap(found.returnOffset), try XCTUnwrap(reference.returnOffset), accuracy: 1e-6)
        }
    }

    func testRestlessAddressFails() throws {
        let found = try XCTUnwrap(features(Self.stroke(contactAt: 8, seconds: 10, still: 0.6), at: 8))

        XCTAssertGreaterThan(found.still, StrokeGate.maxStill)
        XCTAssertFalse(found.passes)
    }

    func testTinyBackswingFails() throws {
        XCTAssertFalse(try XCTUnwrap(features(Self.stroke(contactAt: 8, seconds: 10, backswing: 1), at: 8)).passes)
    }

    /// A chip's backswing is far bigger than any putt's.
    func testChipFails() throws {
        XCTAssertFalse(try XCTUnwrap(features(Self.stroke(contactAt: 8, seconds: 10, backswing: 60), at: 8)).passes)
    }

    /// A contact well before the wrist is back at its address angle is not the putt's.
    func testContactBeforeTheReturnFails() throws {
        let found = try XCTUnwrap(features(Self.stroke(contactAt: 8, seconds: 10), at: 7.85))

        XCTAssertFalse(found.passes)
    }

    /// Missing samples are filled in, so a gap at the contact changes nothing.
    func testGapsAreFilled() throws {
        let samples = Self.stroke(contactAt: 8, seconds: 10)
        let reference = try XCTUnwrap(features(samples, at: 8))
        let gappy = samples.filter { !($0.time > 7.95 && $0.time < 7.97) && !($0.time > 6 && $0.time < 6.02) }
        let found = try XCTUnwrap(features(gappy, at: 8))

        XCTAssertTrue(found.passes)
        XCTAssertEqual(found.backswing, reference.backswing, accuracy: 0.2)
    }

    /// The first seconds of a session have no address to look back on.
    func testTooLittleMotionHasNoFeatures() {
        XCTAssertNil(features(Self.stroke(contactAt: 2, seconds: 4), at: 2))
    }
}
