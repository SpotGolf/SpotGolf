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

    func testSegmentDetailsRoundTripThroughJSON() throws {
        var meta = PuttCapture.Meta(startDate: Date(timeIntervalSince1970: 1_700_000_000), startUptime: 10)
        meta.captureID = UUID()
        meta.roundID = UUID()
        meta.hole = 7
        meta.segment = 3
        meta.endReason = .leftGreen
        meta.wristLocation = "left"
        meta.crownOrientation = "right"
        meta.greenZone = 15

        let decoded = try PuttCapture.Meta(json: meta.json())

        XCTAssertEqual(decoded, meta)
        XCTAssertEqual(decoded.version, 3)
    }

    func testVersionOneCaptureHasNoSegmentDetails() throws {
        var meta = PuttCapture.Meta(startDate: Date(timeIntervalSince1970: 1_700_000_000), startUptime: 10)
        meta.version = 1
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: meta.json()) as? [String: Any])
        for key in ["captureID", "roundID", "hole", "segment", "endReason"] {
            json.removeValue(forKey: key)
        }

        let decoded = try PuttCapture.Meta(json: try JSONSerialization.data(withJSONObject: json))

        XCTAssertEqual(decoded.version, 1)
        XCTAssertNil(decoded.captureID)
        XCTAssertNil(decoded.roundID)
        XCTAssertNil(decoded.hole)
        XCTAssertNil(decoded.segment)
        XCTAssertNil(decoded.endReason)
    }

    func testSegmentFolderName() {
        XCTAssertEqual(PuttCapture.segmentFolder(1, hole: 0), "001-hole0")
        XCTAssertEqual(PuttCapture.segmentFolder(12, hole: 18), "012-hole18")
    }

    func testMarkCSVLine() {
        let mark = PuttCapture.Mark(t: 1.5, label: .practice, date: Date(timeIntervalSince1970: 1_700_000_000.25))

        XCTAssertEqual(mark.csvLine, "1.5,practice,2023-11-14T22:13:20.250Z")
    }
}
