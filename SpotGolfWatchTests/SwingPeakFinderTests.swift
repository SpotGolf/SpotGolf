import XCTest
@testable import SpotGolfWatch

final class SwingPeakFinderTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func readings(_ values: [(TimeInterval, Double)]) -> [SwingPeakFinder.Reading] {
        values.map { SwingPeakFinder.Reading(timestamp: start.addingTimeInterval($0.0), magnitude: $0.1) }
    }

    func testReadingsBelowThresholdAreNotSwings() {
        var finder = SwingPeakFinder()
        XCTAssertTrue(finder.add(readings([(0, 1), (0.1, 2.9), (1, 1), (5, 1)])).isEmpty)
        XCTAssertNil(finder.flush())
    }

    func testPuttIsASwing() {
        var finder = SwingPeakFinder()

        let swings = finder.add(readings([(0, 1), (1.0, 3), (1.1, 3.5), (1.2, 2), (2.0, 1), (4.1, 1)]))

        XCTAssertEqual(swings, [StrokeSuggestion.swing(at: start.addingTimeInterval(1.0), peakG: 3.5)])
    }

    func testSwingStartsAtFirstHighReadingAndKeepsThePeak() {
        var finder = SwingPeakFinder()

        let swings = finder.add(readings([(0, 1), (1.0, 11), (1.1, 15), (1.2, 12), (2.0, 1), (4.1, 1)]))

        XCTAssertEqual(swings, [StrokeSuggestion.swing(at: start.addingTimeInterval(1.0), peakG: 15)])
    }

    func testSwingIsReportedOnceItsCooldownEnds() {
        var finder = SwingPeakFinder()

        XCTAssertTrue(finder.add(readings([(1.0, 11)])).isEmpty)
        XCTAssertTrue(finder.add(readings([(1.2, 16), (3.9, 1)])).isEmpty)
        let swings = finder.add(readings([(4.1, 1)]))

        XCTAssertEqual(swings, [StrokeSuggestion.swing(at: start.addingTimeInterval(1.0), peakG: 16)])
    }

    func testWaggleThenSwingWithinCooldownKeepsTheSwingsForce() {
        var finder = SwingPeakFinder()

        let swings = finder.add(readings([(1.0, 4), (1.3, 2), (2.5, 24), (2.6, 18), (4.1, 1)]))

        XCTAssertEqual(swings, [StrokeSuggestion.swing(at: start.addingTimeInterval(1.0), peakG: 24)])
    }

    func testHighReadingAfterCooldownIsANewSwing() {
        var finder = SwingPeakFinder()

        let swings = finder.add(readings([(1.0, 11), (2.0, 1), (2.5, 13), (3.0, 1), (4.5, 12), (5.5, 1), (7.6, 1)]))

        XCTAssertEqual(swings, [StrokeSuggestion.swing(at: start.addingTimeInterval(1.0), peakG: 13),
                                StrokeSuggestion.swing(at: start.addingTimeInterval(4.5), peakG: 12)])
    }

    func testFlushReturnsASwingWhoseCooldownIsOpen() {
        var finder = SwingPeakFinder()
        XCTAssertTrue(finder.add(readings([(1.0, 11), (1.1, 14)])).isEmpty)

        XCTAssertEqual(finder.flush(), StrokeSuggestion.swing(at: start.addingTimeInterval(1.0), peakG: 14))
        XCTAssertNil(finder.flush())
    }

    func testFlushWithNoSwingReturnsNil() {
        var finder = SwingPeakFinder()
        _ = finder.add(readings([(0, 1), (1.0, 11), (4.1, 1)]))
        XCTAssertNil(finder.flush())
    }
}
