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

    private func run(clickAt: Double?, burstAt: Double, motion: [StrokeGate.Sample]) -> [ContactDetector.Contact] {
        run(clickAt: clickAt, burstAt: burstAt, motion: motion, recordingCandidates: false).contacts
    }

    private func run(clickAt: Double?, burstAt: Double, motion: [StrokeGate.Sample],
                     recordingCandidates: Bool) -> (contacts: [ContactDetector.Contact], judged: [ContactDetector.Judged]) {
        var detector = ContactDetector()
        detector.recordsCandidates = recordingCandidates
        var judged: [ContactDetector.Judged] = []
        let seconds = 14.0
        var found: [ContactDetector.Contact] = []
        let audio = audio(seconds: seconds, clickAt: clickAt)
        let readings = readings(seconds: seconds, burstAt: burstAt)
        // Fed a second at a time, like the watch's batches
        for second in 0..<Int(seconds) {
            let audioStart = second * Int(sampleRate)
            detector.addAudio(Array(audio[audioStart..<(audioStart + Int(sampleRate))]), startTime: Double(second), sampleRate: sampleRate)
            detector.addMotion(Array(motion[(second * 200)..<((second + 1) * 200)]))
            detector.addReadings(Array(readings[(second * 800)..<((second + 1) * 800)]))
            found += detector.evaluate()
            judged += detector.takeJudged()
        }
        return (found + detector.flush(), judged)
    }

    /// Putt Lab records every candidate the gate judged, with what it measured.
    func testRecordedCandidatesCarryTheGatesMeasures() throws {
        let putt = run(clickAt: 11.99, burstAt: 12.0, motion: StrokeGateTests.stroke(contactAt: 12.0, seconds: 14),
                       recordingCandidates: true)
        let turning = (0..<(14 * 200)).map {
            StrokeGate.Sample(time: Double($0) / 200, rotation: SIMD3(0, 0, 1), gravity: SIMD3(0, 0, -1))
        }
        let lift = run(clickAt: 11.99, burstAt: 12.0, motion: turning, recordingCandidates: true)

        XCTAssertEqual(putt.contacts.count, 1)
        XCTAssertGreaterThan(putt.judged.count, 1, "The weaker candidates of the stroke are measured too")
        let best = try XCTUnwrap(putt.judged.max { $0.score < $1.score })
        XCTAssertTrue(best.passed)
        XCTAssertEqual(best.time, putt.contacts[0].time)
        XCTAssertEqual(try XCTUnwrap(best.features).backswing, 12, accuracy: 1)
        XCTAssertEqual(lift.contacts, [])
        XCTAssertFalse(lift.judged.isEmpty)
        XCTAssertFalse(lift.judged.contains { $0.passed })
    }

    func testCandidatesAreNotKeptUnlessAsked() {
        let putt = run(clickAt: 11.99, burstAt: 12.0, motion: StrokeGateTests.stroke(contactAt: 12.0, seconds: 14),
                       recordingCandidates: false)

        XCTAssertEqual(putt.contacts.count, 1)
        XCTAssertEqual(putt.judged, [])
    }

    func testPuttIsAContact() {
        let found = run(clickAt: 11.99, burstAt: 12.0, motion: StrokeGateTests.stroke(contactAt: 12.0, seconds: 14))

        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].time, 12.0, accuracy: 0.03)
        XCTAssertGreaterThan(found[0].score, ContactDetector.minRecordedScore)
        XCTAssertGreaterThan(found[0].click, 10)
        XCTAssertGreaterThan(found[0].turning, 0.5)
    }

    func testBurstWithoutClickIsNotAContact() {
        XCTAssertEqual(run(clickAt: nil, burstAt: 12.0, motion: StrokeGateTests.stroke(contactAt: 12.0, seconds: 14)), [])
    }

    func testClickAwayFromTheBurstIsNotAContact() {
        XCTAssertEqual(run(clickAt: 11.5, burstAt: 12.0, motion: StrokeGateTests.stroke(contactAt: 12.0, seconds: 14)), [])
    }

    /// The burst peaks after the click; a click well after the burst started is something else.
    func testClickAfterTheBurstIsNotAContact() {
        XCTAssertEqual(run(clickAt: 12.03, burstAt: 12.0, motion: StrokeGateTests.stroke(contactAt: 12.0, seconds: 14)), [])
    }

    /// A click and a burst with the wrist turning steadily, as when lifting it: no putting stroke.
    func testNoStrokeIsNotAContact() {
        let turning = (0..<(14 * 200)).map {
            StrokeGate.Sample(time: Double($0) / 200, rotation: SIMD3(0, 0, 1), gravity: SIMD3(0, 0, -1))
        }
        XCTAssertEqual(run(clickAt: 11.99, burstAt: 12.0, motion: turning), [])
    }

    /// With no audio or motion, candidates are not kept beyond `maxWait`.
    func testCandidatesAreDroppedWhenNoAudioComes() {
        var detector = ContactDetector()
        let readings = readings(seconds: 20, burstAt: 5)
        for second in 0..<20 {
            detector.addReadings(Array(readings[(second * 800)..<((second + 1) * 800)]))
            _ = detector.evaluate()
        }

        XCTAssertEqual(detector.pendingCandidates, 0)
    }
}
