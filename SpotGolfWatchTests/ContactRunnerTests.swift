import XCTest
@testable import SpotGolfWatch

final class ContactRunnerTests: XCTestCase {

    private func contact(at time: Double) -> ContactDetector.Contact {
        ContactDetector.Contact(time: time, score: 10, burst: 0.5, click: 20, turning: 0.1)
    }

    func testContactsNearATapAreDropped() {
        let taps = TapGuard()
        taps.tapped(atUptime: 100)
        let kept = ContactRunner.untapped([contact(at: 98.9), contact(at: 99.5), contact(at: 101), contact(at: 101.1)], taps: taps)
        XCTAssertEqual(kept.map(\.time), [98.9, 101.1])
    }

    /// A tap registered after its knock's batch arrived still drops the contact when it is reported.
    func testTapAfterTheContactDropsIt() {
        let taps = TapGuard()
        let contacts = [contact(at: 50)]
        XCTAssertEqual(ContactRunner.untapped(contacts, taps: taps).count, 1)
        taps.tapped(atUptime: 50.4)
        XCTAssertTrue(ContactRunner.untapped(contacts, taps: taps).isEmpty)
    }
}
