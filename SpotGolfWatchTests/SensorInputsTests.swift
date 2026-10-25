import SensorSources
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

    @MainActor
    func testZerosAreDataButNotRealData() {
        let hub = MockSensorHub(inbox: nil)
        hub.setMode(.zeros, for: .accelerometer)
        let sensors = SensorInputs(sources: .mocks(hub: hub))
        let subscription = sensors.subscribeAccelerometer { _ in }

        let delivered = expectation(description: "a batch")
        Task { @MainActor in
            while !sensors.hasSentData(.accelerometer) {
                try? await Task.sleep(for: .milliseconds(50))
            }
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 3)

        XCTAssertFalse(sensors.isSendingRealData(.accelerometer))
        hub.setMode(nil, for: .accelerometer)
        subscription.cancel()
        XCTAssertFalse(sensors.hasSentData(.accelerometer))
    }
}
