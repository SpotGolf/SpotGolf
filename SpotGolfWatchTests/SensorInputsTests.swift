import XCTest
@testable import SpotGolfWatch

@MainActor
final class SensorInputsTests: XCTestCase {

    func testLastHighGIsTheLastReadingOverTheThreshold() {
        let readings: [(uptime: Double, magnitude: Double)] = [
            (1, 0.9), (2, 18.4), (3, 1.1), (4, 12.25), (5, 2.0)
        ]
        let highG = SensorInputs.lastHighG(in: readings)
        XCTAssertEqual(highG?.magnitude, 12.25)
        XCTAssertEqual(highG?.date.timeIntervalSinceReferenceDate ?? 0,
                       Uptime.date(at: 4).timeIntervalSinceReferenceDate, accuracy: 0.1)
    }

    func testReadingAtTheThresholdIsNotOverIt() {
        XCTAssertNil(SensorInputs.lastHighG(in: [(1, 10), (2, 9.99)]))
    }

    func testNoReadingsGivesNil() {
        XCTAssertNil(SensorInputs.lastHighG(in: []))
    }
}
