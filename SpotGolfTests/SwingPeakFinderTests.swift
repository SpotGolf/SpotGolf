import XCTest
@testable import SpotGolf

final class SwingPeakFinderTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func readings(_ values: [(TimeInterval, Double)]) -> [SwingPeakFinder.Reading] {
        values.map { SwingPeakFinder.Reading(timestamp: start.addingTimeInterval($0.0), magnitude: $0.1) }
    }

    func testReadingsBelowThresholdAreNotSwings() {
        var finder = SwingPeakFinder()
        XCTAssertTrue(finder.add(readings([(0, 1), (0.1, 9.9), (1, 1)])).isEmpty)
    }

    func testSwingStartsAtFirstHighReadingAndKeepsThePeak() {
        var finder = SwingPeakFinder()

        let swings = finder.add(readings([(0, 1), (1.0, 11), (1.1, 15), (1.2, 12), (2.0, 1)]))

        XCTAssertEqual(swings, [Swing(timestamp: start.addingTimeInterval(1.0), peakG: 15)])
    }

    func testSwingSpanningBatchesIsReportedOnceItsPeakWindowCloses() {
        var finder = SwingPeakFinder()

        XCTAssertTrue(finder.add(readings([(1.0, 11)])).isEmpty)
        let swings = finder.add(readings([(1.2, 16), (1.8, 1)]))

        XCTAssertEqual(swings, [Swing(timestamp: start.addingTimeInterval(1.0), peakG: 16)])
    }

    func testHighReadingsWithinCooldownAreTheSameSwing() {
        var finder = SwingPeakFinder()

        let swings = finder.add(readings([(1.0, 11), (2.0, 1), (2.5, 13), (3.0, 1), (4.5, 12), (5.5, 1)]))

        XCTAssertEqual(swings.map(\.timestamp), [start.addingTimeInterval(1.0), start.addingTimeInterval(4.5)])
    }
}
