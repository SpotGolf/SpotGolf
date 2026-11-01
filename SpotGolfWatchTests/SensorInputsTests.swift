import SensorSources
import XCTest
@testable import SpotGolfWatch

@MainActor
final class SensorInputsTests: XCTestCase {

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
