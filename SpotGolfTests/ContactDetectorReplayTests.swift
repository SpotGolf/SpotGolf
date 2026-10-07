import XCTest
@testable import SpotGolf

/// Replays the Putt Lab captures of 2026-10-06 through `ContactDetector`, fed the way the
/// watch feeds it, and checks the strokes it finds against the player's marks. The captures
/// live unzipped in the git-ignored `Data` folder, so this is skipped where they are missing.
final class ContactDetectorReplayTests: XCTestCase {

    private static let dataDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Data")

    /// How many marks of each label had a contact of the given score in the window before them.
    private struct Tally: Equatable {
        var putt = 0
        var practice = 0
        var ground = 0
    }

    private func tally(capture: String, windowEnd: Double, score: Double) throws -> (found: Tally, marks: Tally) {
        let folder = Self.dataDirectory.appendingPathComponent(capture)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: folder.appendingPathComponent(PuttCapture.audioFile).path),
                          "The capture is not on this machine")
        let meta = try PuttCapture.Meta(json: Data(contentsOf: folder.appendingPathComponent(PuttCapture.metaFile)))
        let audio = try XCTUnwrap(meta.audio)
        let readings = try records(folder.appendingPathComponent(PuttCapture.accelFile), size: PuttCapture.AccelSample.size) { data in
            PuttCapture.AccelSample(record: data).map { ContactDetector.Reading(time: $0.t, x: Double($0.x), y: Double($0.y), z: Double($0.z)) }
        }
        let rotations = try records(folder.appendingPathComponent(PuttCapture.motionFile), size: PuttCapture.MotionSample.size) { data in
            PuttCapture.MotionSample(record: data).map { sample in
                let r = sample.values
                return ContactDetector.Rotation(time: sample.t, rate: Double((r[0] * r[0] + r[1] * r[1] + r[2] * r[2]).squareRoot()))
            }
        }
        let samples = try wavSamples(folder.appendingPathComponent(PuttCapture.audioFile))

        var detector = ContactDetector()
        var contacts: [ContactDetector.Contact] = []
        var nextReading = 0, nextRotation = 0, nextSample = 0
        let bufferFrames = 4096
        let end = meta.duration ?? readings.last?.time ?? 0
        var second = 1.0
        while second <= end + 1 {
            while nextSample < samples.count, audio.startTime + Double(nextSample) / audio.sampleRate < second {
                let count = min(bufferFrames, samples.count - nextSample)
                detector.addAudio(Array(samples[nextSample..<(nextSample + count)]),
                                  startTime: audio.startTime + Double(nextSample) / audio.sampleRate, sampleRate: audio.sampleRate)
                nextSample += count
            }
            let rotationEnd = rotations[nextRotation...].firstIndex { $0.time >= second } ?? rotations.count
            detector.addRotations(Array(rotations[nextRotation..<rotationEnd]))
            nextRotation = rotationEnd
            let readingEnd = readings[nextReading...].firstIndex { $0.time >= second } ?? readings.count
            detector.addReadings(Array(readings[nextReading..<readingEnd]))
            nextReading = readingEnd
            contacts += detector.evaluate()
            second += 1
        }
        contacts += detector.flush()

        var found = Tally()
        var marks = Tally()
        var previous = 2.5
        for mark in meta.marks {
            let start = max(previous, mark.t - 5), stop = mark.t - windowEnd
            previous = mark.t + 0.8
            let hit = contacts.contains { $0.time >= start && $0.time <= stop && $0.score >= score }
            switch mark.label {
            case .putt: marks.putt += 1; if hit { found.putt += 1 }
            case .practice: marks.practice += 1; if hit { found.practice += 1 }
            case .ground: marks.ground += 1; if hit { found.ground += 1 }
            }
        }
        return (found, marks)
    }

    /// Indoors: every putt and no practice stroke, at the phone's putt line.
    func testIndoorCapture() throws {
        let (found, marks) = try tally(capture: "putt-capture-2026-10-06T162828", windowEnd: 0.5, score: 2.7)

        XCTAssertEqual(marks, Tally(putt: 15, practice: 15, ground: 0))
        XCTAssertEqual(found, Tally(putt: 15, practice: 0, ground: 0))
    }

    /// Outdoors: every full-length putt, with the soft tap-ins under the line, and one practice
    /// stroke over it. The script's capture-wide background let one grass brush over at 2.8;
    /// the rolling background here keeps it under.
    func testOutdoorCapture() throws {
        let (found, marks) = try tally(capture: "putt-capture-2026-10-06T172603", windowEnd: 1.0, score: 2.7)

        XCTAssertEqual(marks, Tally(putt: 41, practice: 14, ground: 8))
        XCTAssertEqual(found, Tally(putt: 29, practice: 1, ground: 0))
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
