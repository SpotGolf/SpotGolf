import XCTest
@testable import SpotGolf

final class PuttCaptureTests: XCTestCase {

    func testAccelSampleRoundTrips() {
        let sample = PuttCapture.AccelSample(t: 12.3456789, x: -0.5, y: 1.25, z: 3)
        var data = Data()
        sample.append(to: &data)

        XCTAssertEqual(data.count, PuttCapture.AccelSample.size)
        XCTAssertEqual(PuttCapture.AccelSample(record: data), sample)
        XCTAssertNil(PuttCapture.AccelSample(record: data.dropLast()))
    }

    func testMotionSampleRoundTrips() {
        let values = (0..<13).map { Float($0) * 0.5 - 2 }
        let sample = PuttCapture.MotionSample(t: 0.005, values: values)
        var data = Data()
        sample.append(to: &data)

        XCTAssertEqual(data.count, PuttCapture.MotionSample.size)
        XCTAssertEqual(PuttCapture.MotionSample(record: data), sample)
    }

    func testMetaRoundTripsThroughJSON() throws {
        var meta = PuttCapture.Meta(startDate: Date(timeIntervalSince1970: 1_700_000_000), startUptime: 5000.25)
        meta.endDate = Date(timeIntervalSince1970: 1_700_000_600)
        meta.duration = 600
        meta.audio = PuttCapture.Audio(sampleRate: 48000, channels: 1, startTime: 0.1, startHostTime: 5000.35, startUptime: 5000.4)
        meta.accelCount = 480_000
        meta.marks = [PuttCapture.Mark(t: 10, label: .putt, date: Date(timeIntervalSince1970: 1_700_000_010))]

        let decoded = try PuttCapture.Meta(json: meta.json())

        XCTAssertEqual(decoded, meta)
        XCTAssertEqual(decoded.version, PuttCapture.version)
    }

    func testMarkCSVLine() {
        let mark = PuttCapture.Mark(t: 1.5, label: .practice, date: Date(timeIntervalSince1970: 1_700_000_000.25))

        XCTAssertEqual(mark.csvLine, "1.5,practice,2023-11-14T22:13:20.250Z")
    }
}
