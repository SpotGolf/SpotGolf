import XCTest
@testable import SpotGolf

/// Replays Developer Mode captures through `ContactDetector`, fed the way the watch feeds it, and
/// checks the strokes it finds against the player's marks and labels. The captures live in the
/// git-ignored `Data` folder, so these are skipped where they are missing.
final class ContactDetectorReplayTests: XCTestCase {

    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let dataDirectory = root.appendingPathComponent("Data")
    private static let bearDance = dataDirectory.appendingPathComponent("putt-captures/42A9900B-FEF0-4F98-8487-B0BFCE400C64")
    /// The Bear Dance round's putts and other events, labeled by hand for the 2026-10-16 analysis.
    private static let bearDanceLabels = root.appendingPathComponent("TestFixtures/bear-dance-putt-labels.json")

    /// How many marks of each label had a contact in the window before them.
    private struct Tally: Equatable {
        var putt = 0
        var practice = 0
        var ground = 0
    }

    private func tally(capture: String, windowEnd: Double) throws -> (found: Tally, marks: Tally) {
        let folder = Self.dataDirectory.appendingPathComponent(capture)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: folder.appendingPathComponent(PuttCapture.audioFile).path),
                          "The capture is not on this machine")
        let meta = try PuttCapture.Meta(json: Data(contentsOf: folder.appendingPathComponent(PuttCapture.metaFile)))
        let contacts = try replay(folder)

        var found = Tally()
        var marks = Tally()
        var previous = 2.5
        for mark in meta.marks {
            let start = max(previous, mark.t - 5), stop = mark.t - windowEnd
            previous = mark.t + 0.8
            let hit = contacts.contains { $0.time >= start && $0.time <= stop }
            switch mark.label {
            case .putt: marks.putt += 1; if hit { found.putt += 1 }
            case .practice: marks.practice += 1; if hit { found.practice += 1 }
            case .ground: marks.ground += 1; if hit { found.ground += 1 }
            }
        }
        return (found, marks)
    }

    /// Indoors: every putt, and no practice stroke.
    func testIndoorCapture() throws {
        let (found, marks) = try tally(capture: "putt-capture-2026-10-06T162828", windowEnd: 0.5)

        XCTAssertEqual(marks, Tally(putt: 15, practice: 15, ground: 0))
        XCTAssertEqual(found, Tally(putt: 15, practice: 0, ground: 0))
    }

    /// Outdoors: all but two putts, the soft tap-ins included, and no stroke that brushed the
    /// grass. Two practice strokes pass.
    func testOutdoorCapture() throws {
        let (found, marks) = try tally(capture: "putt-capture-2026-10-06T172603", windowEnd: 1.0)

        XCTAssertEqual(marks, Tally(putt: 41, practice: 14, ground: 8))
        XCTAssertEqual(found, Tally(putt: 39, practice: 2, ground: 0))
    }

    /// The Bear Dance round of 2026-10-13: every one of the player's 31 putts, and none of the
    /// 177 other contacts the watch recorded live. Mark taps are guarded as the watch guards
    /// them. The capture's own contact haptics, which a round no longer plays, are left out.
    func testBearDanceRound() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.bearDance.path), "The capture is not on this machine")
        let labels = try JSONDecoder().decode(Labels.self, from: Data(contentsOf: Self.bearDanceLabels))
        var putts = 0, found = 0
        var others: [String] = []
        for (name, segment) in labels.segments.sorted(by: { $0.key < $1.key }) {
            let folder = Self.bearDance.appendingPathComponent(name)
            let meta = try PuttCapture.Meta(json: Data(contentsOf: folder.appendingPathComponent(PuttCapture.metaFile)))
            // The watch's TapGuard window is 1 s each side of a tap
            let skipped = meta.marks.map { ($0.t - 1)...($0.t + 1) }
                + segment.haptics.map { ($0.t - 0.05)...($0.t + 0.8) }
            let contacts = try replay(folder, drift: labels.audioDriftPPM / 1e6, gaps: segment.audioGaps, skipped: skipped)
            putts += segment.putts.count
            found += segment.putts.filter { putt in contacts.contains { abs($0.time - putt.t) <= 0.1 } }.count
            for contact in contacts where !segment.putts.contains(where: { abs(contact.time - $0.t) <= 0.1 }) {
                others.append("\(name) at \(contact.time)")
            }
        }

        XCTAssertEqual(putts, 31)
        XCTAssertEqual(found, 31)
        XCTAssertEqual(others, [])
    }

    // MARK: - Replay

    private struct Labels: Decodable {
        struct Event: Decodable {
            let t: Double
        }

        struct AudioGap: Decodable {
            /// Where in the WAV the gap starts.
            let sample: Int
            let seconds: Double
        }

        struct Segment: Decodable {
            let putts: [Event]
            let haptics: [Event]
            let audioGaps: [AudioGap]
        }

        let audioDriftPPM: Double
        let segments: [String: Segment]
    }

    /// The contacts the detector finds in a capture segment, fed a second at a time like the
    /// watch's batches. `drift` corrects the WAV's clock, `gaps` puts back audio the WAV lost,
    /// and readings and contacts in `skipped` are dropped, as `TapGuard` drops them.
    private func replay(_ folder: URL, drift: Double = 0, gaps: [Labels.AudioGap] = [],
                        skipped: [ClosedRange<Double>] = []) throws -> [ContactDetector.Contact] {
        let meta = try PuttCapture.Meta(json: Data(contentsOf: folder.appendingPathComponent(PuttCapture.metaFile)))
        let audio = try XCTUnwrap(meta.audio)
        let sampleRate = audio.sampleRate / (1 - drift)
        let readings = try records(folder.appendingPathComponent(PuttCapture.accelFile), size: PuttCapture.AccelSample.size) { data in
            PuttCapture.AccelSample(record: data).map { ContactDetector.Reading(time: $0.t, x: Double($0.x), y: Double($0.y), z: Double($0.z)) }
        }.filter { reading in !skipped.contains { $0.contains(reading.time) } }
        let motion = try records(folder.appendingPathComponent(PuttCapture.motionFile), size: PuttCapture.MotionSample.size) { data in
            PuttCapture.MotionSample(record: data).map { sample in
                let v = sample.values.map(Double.init)
                return StrokeGate.Sample(time: sample.t, rotation: SIMD3(v[0], v[1], v[2]), gravity: SIMD3(v[6], v[7], v[8]))
            }
        }
        var samples = try wavSamples(folder.appendingPathComponent(PuttCapture.audioFile))
        for gap in gaps.sorted(by: { $0.sample > $1.sample }) {
            samples.insert(contentsOf: [Float](repeating: 0, count: Int((gap.seconds * sampleRate).rounded())), at: gap.sample)
        }

        var detector = ContactDetector()
        var contacts: [ContactDetector.Contact] = []
        var nextReading = 0, nextMotion = 0, nextSample = 0
        let bufferFrames = 4096
        let end = max(readings.last?.time ?? 0, motion.last?.time ?? 0)
        var second = 1.0
        while second <= end + 2 {
            while nextSample < samples.count, audio.startTime + Double(nextSample) / sampleRate < second {
                let count = min(bufferFrames, samples.count - nextSample)
                detector.addAudio(Array(samples[nextSample..<(nextSample + count)]),
                                  startTime: audio.startTime + Double(nextSample) / sampleRate, sampleRate: sampleRate)
                nextSample += count
            }
            let motionEnd = motion[nextMotion...].firstIndex { $0.time >= second } ?? motion.count
            detector.addMotion(Array(motion[nextMotion..<motionEnd]))
            nextMotion = motionEnd
            let readingEnd = readings[nextReading...].firstIndex { $0.time >= second } ?? readings.count
            detector.addReadings(Array(readings[nextReading..<readingEnd]))
            nextReading = readingEnd
            contacts += detector.evaluate()
            second += 1
        }
        contacts += detector.flush()
        return contacts.filter { contact in !skipped.contains { $0.contains(contact.time) } }
    }

    // MARK: - Files

    private func records<T>(_ url: URL, size: Int, _ decode: (Data) -> T?) throws -> [T] {
        let data = try Data(contentsOf: url)
        return (0..<(data.count / size)).compactMap { decode(data[(data.startIndex + $0 * size)..<(data.startIndex + ($0 + 1) * size)]) }
    }

    /// The first channel of a 16-bit PCM WAV, in full-scale units.
    private func wavSamples(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        var offset = 12
        var channels = 1
        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
            let size = Int(data.littleEndianInteger(at: offset + 4) as UInt32)
            if id == "fmt " {
                channels = Int(data.littleEndianInteger(at: offset + 10) as UInt16)
            } else if id == "data" {
                let frames = min(size, data.count - offset - 8) / (2 * channels)
                let stride = 2 * channels
                return data.withUnsafeBytes { raw -> [Float] in
                    let base = raw.baseAddress!.advanced(by: offset + 8)
                    return (0..<frames).map { Float(Int16(littleEndian: base.loadUnaligned(fromByteOffset: $0 * stride, as: Int16.self))) / 32768 }
                }
            }
            offset += 8 + size + size % 2
        }
        throw CocoaError(.fileReadCorruptFile)
    }
}
