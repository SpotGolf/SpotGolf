import XCTest
@testable import SpotGolf

final class ContactDetectorTests: XCTestCase {
    private let sampleRate = 48_000.0

    /// Quiet noise with a click at `clickAt`: 2 ms of noise 30 times louder.
    private func audio(seconds: Double, clickAt: Double?) -> [Float] {
        var samples: [Float] = []
        var state: UInt32 = 12345
        func noise() -> Float {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Float(Int32(bitPattern: state) >> 8) / Float(1 << 23)
        }
        for n in 0..<Int(seconds * sampleRate) {
            let t = Double(n) / sampleRate
            let loud = clickAt.map { t >= $0 && t < $0 + 0.002 } ?? false
            samples.append(noise() * (loud ? 0.03 : 0.001))
        }
        return samples
    }

    /// Gravity on z with a 20 ms ring of 0.3 g at `burstAt`.
    private func readings(seconds: Double, burstAt: Double) -> [ContactDetector.Reading] {
        (0..<Int(seconds * 800)).map { k in
            let t = Double(k) / 800
            let ring = t >= burstAt && t < burstAt + 0.02 ? 0.3 * sin((t - burstAt) * 2 * .pi * 300) : 0
            return ContactDetector.Reading(time: t, x: ring, y: 0, z: 1)
        }
    }

    private func rotations(seconds: Double, rate: Double) -> [ContactDetector.Rotation] {
        (0..<Int(seconds * 200)).map { ContactDetector.Rotation(time: Double($0) / 200, rate: rate) }
    }

    private func run(clickAt: Double?, burstAt: Double, turning: Double) -> [ContactDetector.Contact] {
        var detector = ContactDetector()
        let seconds = 14.0
        var found: [ContactDetector.Contact] = []
        let audio = audio(seconds: seconds, clickAt: clickAt)
        let readings = readings(seconds: seconds, burstAt: burstAt)
        let rotations = rotations(seconds: seconds, rate: turning)
        // Fed a second at a time, like the watch's batches
        for second in 0..<Int(seconds) {
            let audioStart = second * Int(sampleRate)
            detector.addAudio(Array(audio[audioStart..<(audioStart + Int(sampleRate))]), startTime: Double(second), sampleRate: sampleRate)
            detector.addRotations(Array(rotations[(second * 200)..<((second + 1) * 200)]))
            detector.addReadings(Array(readings[(second * 800)..<((second + 1) * 800)]))
            found += detector.evaluate()
        }
        return found + detector.flush()
    }

    func testClickAndBurstTogetherWhileTurningIsAContact() {
        let found = run(clickAt: 12.0, burstAt: 12.0, turning: 1.0)

        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].time, 12.0, accuracy: 0.01)
        XCTAssertGreaterThan(found[0].score, ContactDetector.minRecordedScore)
        XCTAssertGreaterThan(found[0].click, 10)
        XCTAssertEqual(found[0].turning, 1.0, accuracy: 0.001)
    }

    func testBurstWithoutClickIsNotAContact() {
        XCTAssertEqual(run(clickAt: nil, burstAt: 12.0, turning: 1.0), [])
    }

    func testClickAwayFromTheBurstIsNotAContact() {
        XCTAssertEqual(run(clickAt: 12.5, burstAt: 12.0, turning: 1.0), [])
    }

    /// With no audio or rotation, candidates are not kept beyond `maxWait`.
    func testCandidatesAreDroppedWhenNoAudioComes() {
        var detector = ContactDetector()
        let readings = readings(seconds: 20, burstAt: 5)
        for second in 0..<20 {
            detector.addReadings(Array(readings[(second * 800)..<((second + 1) * 800)]))
            _ = detector.evaluate()
        }

        XCTAssertEqual(detector.pendingCandidates, 0)
    }

    func testStillWristIsNotAContact() {
        XCTAssertEqual(run(clickAt: 12.0, burstAt: 12.0, turning: 0.1), [])
    }
}
